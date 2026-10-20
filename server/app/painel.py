"""Painel de acompanhamento em tempo real (interface web do administrador).

É um serviço SEPARADO da API pública (`app.main`): roda em outra porta, publicada só em
127.0.0.1 no Docker Compose, e NÃO passa pelo túnel da Cloudflare. Assim o link público
aleatório expõe apenas a API de coleta, nunca este painel.

Mostra: total e ritmo de respostas, níveis de risco, sintomas mais relatados, série por hora,
últimas respostas (anônimas), mapa de áreas (~1 km), estado do servidor e o link atual do túnel
(com QR code) para conectar o app.

Privacidade: o painel lê o mesmo banco da API, que não guarda identificação nenhuma. Diferente
da API pública, aqui NÃO se aplica o mínimo de respostas para divulgar (é visão do administrador);
por isso exige `ADMIN_TOKEN` quando definido, e deve ficar acessível só a quem administra.

Execução local:  uvicorn app.painel:app --port 8080
"""

from __future__ import annotations

import datetime as dt
import io
import re
import secrets
import time
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Any, Callable

import requests
import segno
from fastapi import Depends, FastAPI, Header, HTTPException, Query, Request, Response
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from sqlalchemy import Engine, case, func, select, text
from sqlalchemy.orm import Session, selectinload

from . import stats
from .config import Settings
from .db import make_engine, make_session_factory
from .models import NIVEIS, Resposta, RespostaSintoma
from .ratelimit import RateLimiter

STATIC_DIR = Path(__file__).parent / "static"

#: Rótulos dos sintomas do questionário do app (lib/logic/risk_assessment.dart).
#: Identificadores desconhecidos aparecem com o próprio id.
SINTOMA_ROTULOS = {
    "cough": "Tosse",
    "throat": "Irritação ou dor na garganta",
    "nose": "Coriza ou nariz irritado",
    "wheeze": "Chiado no peito",
    "dyspnea": "Falta de ar",
    "eyes": "Olhos ardendo, vermelhos ou lacrimejando",
    "chest": "Aperto ou dor no peito",
    "palpitation": "Palpitações ou batimentos irregulares",
    "headache": "Dor de cabeça",
    "dizzy": "Tontura ou confusão",
    "fatigue": "Cansaço fora do normal",
}

_HOST = re.compile(r"^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$")


def _aware(value: dt.datetime) -> dt.datetime:
    """SQLite devolve datas sem fuso; no PostgreSQL já vêm com fuso. Tudo em UTC."""
    return value.replace(tzinfo=dt.timezone.utc) if value.tzinfo is None else value.astimezone(dt.timezone.utc)


# ---------------------------------------------------------------------- consultas


def resumo(session: Session, agora: dt.datetime) -> dict[str, Any]:
    def contar(desde: dt.datetime | None) -> int:
        q = select(func.count()).select_from(Resposta)
        if desde is not None:
            q = q.where(Resposta.criado_em >= desde)
        return int(session.scalar(q) or 0)

    d24, d30, h1 = agora - dt.timedelta(hours=24), agora - dt.timedelta(days=30), agora - dt.timedelta(hours=1)

    def niveis(desde: dt.datetime) -> dict[str, int]:
        out = {n: 0 for n in NIVEIS}
        for nivel, qtd in session.execute(
            select(Resposta.nivel, func.count()).where(Resposta.criado_em >= desde).group_by(Resposta.nivel)
        ):
            out[nivel] = int(qtd)
        return out

    total_30d = contar(d30)
    g = RespostaSintoma.gravidade
    rows = session.execute(
        select(
            RespostaSintoma.sintoma,
            func.sum(case((g >= 1, 1), else_=0)),
            func.sum(case((g == 1, 1), else_=0)),
            func.sum(case((g == 2, 1), else_=0)),
            func.sum(case((g == 3, 1), else_=0)),
            func.avg(case((g >= 1, g))),
        )
        .join(Resposta, Resposta.id == RespostaSintoma.resposta_id)
        .where(Resposta.criado_em >= d30)
        .group_by(RespostaSintoma.sintoma)
    ).all()
    sintomas = [
        {
            "id": s,
            "rotulo": SINTOMA_ROTULOS.get(s, s),
            "relatos": int(rel or 0),
            "percentual": round(100 * int(rel or 0) / total_30d, 1) if total_30d else 0.0,
            "leve": int(leve or 0),
            "moderado": int(mod or 0),
            "intenso": int(intn or 0),
            "gravidade_media": None if media is None else round(float(media), 2),
        }
        for s, rel, leve, mod, intn, media in rows
    ]
    sintomas.sort(key=lambda x: (-x["relatos"], x["id"]))

    perfil = session.execute(
        select(
            func.sum(case((Resposta.idoso, 1), else_=0)),
            func.sum(case((Resposta.gestante, 1), else_=0)),
            func.sum(case((Resposta.crianca, 1), else_=0)),
            func.sum(case((Resposta.doenca_respiratoria, 1), else_=0)),
            func.sum(case((Resposta.doenca_cardiaca, 1), else_=0)),
        ).where(Resposta.criado_em >= d30)
    ).one()

    ultima = session.scalar(select(func.max(Resposta.criado_em)))
    return {
        "total": contar(None),
        "ultimas_24h": contar(d24),
        "ultima_hora": contar(h1),
        "total_30d": total_30d,
        "ultima_resposta": None if ultima is None else _aware(ultima).isoformat(),
        "niveis_24h": niveis(d24),
        "niveis_30d": niveis(d30),
        "sintomas_30d": sintomas,
        "perfil_30d": dict(
            zip(("idoso", "gestante", "crianca", "doenca_respiratoria", "doenca_cardiaca"),
                (int(v or 0) for v in perfil))
        ),
    }


def serie_horaria(session: Session, agora: dt.datetime, horas: int = 48) -> list[dict[str, Any]]:
    """Respostas por hora (UTC), com as horas vazias incluídas (zero)."""
    inicio = agora.replace(minute=0, second=0, microsecond=0) - dt.timedelta(hours=horas - 1)
    baldes = {inicio + dt.timedelta(hours=i): 0 for i in range(horas)}
    for (criado,) in session.execute(select(Resposta.criado_em).where(Resposta.criado_em >= inicio)):
        chave = _aware(criado).replace(minute=0, second=0, microsecond=0)
        if chave in baldes:
            baldes[chave] += 1
    return [{"hora": h.isoformat(), "respostas": n} for h, n in baldes.items()]


def recentes(session: Session, limite: int = 20) -> list[dict[str, Any]]:
    rows = session.scalars(
        select(Resposta).options(selectinload(Resposta.sintomas)).order_by(Resposta.id.desc()).limit(limite)
    ).all()
    out = []
    for r in rows:
        graus = sorted(
            ({"id": s.sintoma, "rotulo": SINTOMA_ROTULOS.get(s.sintoma, s.sintoma), "gravidade": s.gravidade}
             for s in r.sintomas if s.gravidade >= 1),
            key=lambda x: (-x["gravidade"], x["id"]),
        )
        out.append(
            {
                "id": r.id,
                "criado_em": _aware(r.criado_em).isoformat(),
                "nivel": r.nivel,
                "pontos": r.pontos,
                "exposicao": r.exposicao,
                "lat": None if r.lat is None else float(r.lat),
                "lon": None if r.lon is None else float(r.lon),
                "perfil": [n for n in ("idoso", "gestante", "crianca", "doenca_respiratoria", "doenca_cardiaca")
                           if getattr(r, n)],
                "sintomas": graus,
                "app_version": r.app_version,
            }
        )
    return out


def mapa_admin(session: Session, agora: dt.datetime, horas: int = 72) -> list[dict[str, Any]]:
    """Áreas de ~1 km com respostas, SEM o mínimo por célula da API pública (visão do administrador)."""
    m = stats.mapa(session, horas=horas, minimo_celula=1, agora=agora)
    return [c.model_dump() for c in m.celulas]


# ------------------------------------------------------------------------- túnel


def descobrir_link(settings: Settings, http_get: Callable[..., Any] = requests.get) -> dict[str, Any]:
    """Link público atual da API.

    - `PUBLIC_URL` definido (túnel nomeado/domínio próprio): usa-o, fixo.
    - Senão consulta o `cloudflared` (`/quicktunnel` no servidor de métricas), que informa o
      endereço aleatório `*.trycloudflare.com` sorteado quando o túnel iniciou.
    """
    if settings.public_url:
        return {"url": settings.public_url, "aleatorio": False, "estado": "fixo (PUBLIC_URL)"}
    if not settings.tunnel_metrics_url:
        return {"url": None, "aleatorio": False, "estado": "túnel não configurado"}
    try:
        resp = http_get(f"{settings.tunnel_metrics_url}/quicktunnel", timeout=2)
        resp.raise_for_status()
        host = str(resp.json().get("hostname", "")).strip().lower()
    except Exception:  # noqa: BLE001 - rede/JSON: o painel só mostra o estado
        return {"url": None, "aleatorio": True, "estado": "túnel indisponível"}
    if not host:
        return {"url": None, "aleatorio": True, "estado": "aguardando o túnel iniciar"}
    if not _HOST.match(host):
        return {"url": None, "aleatorio": True, "estado": "endereço do túnel inválido"}
    return {"url": f"https://{host}", "aleatorio": True, "estado": "ativo"}


# --------------------------------------------------------------------------- app


def create_painel_app(settings: Settings | None = None, engine: Engine | None = None) -> FastAPI:
    settings = settings or Settings.from_env()
    owns_engine = engine is None
    engine = engine or make_engine(settings.database_url)
    session_factory = make_session_factory(engine)
    iniciado = time.monotonic()

    @asynccontextmanager
    async def lifespan(_: FastAPI):
        yield
        if owns_engine:  # um engine injetado (testes) é de quem o criou
            engine.dispose()

    app = FastAPI(
        title="Alerta Fumaça AM — Painel",
        docs_url=None, redoc_url=None, openapi_url=None,
        lifespan=lifespan,
    )
    app.state.settings = settings
    app.state.falhas = RateLimiter(10)  # tentativas de token inválidas por minuto, por origem
    app.state.link_cache = (0.0, {})

    def sessao():
        with session_factory() as s:
            yield s

    def exigir_acesso(request: Request, x_admin_token: str | None = Header(default=None)) -> None:
        esperado = settings.admin_token
        if not esperado:
            return  # sem token: o painel só deve estar acessível localmente (Compose: 127.0.0.1)
        if x_admin_token and secrets.compare_digest(x_admin_token, esperado):
            return
        origem = request.client.host if request.client else "?"
        if not app.state.falhas.allow(origem):
            raise HTTPException(status_code=429, detail="Muitas tentativas. Aguarde um minuto.")
        raise HTTPException(status_code=401, detail="Token inválido.")

    def link_atual() -> dict[str, Any]:
        quando, valor = app.state.link_cache
        if time.monotonic() - quando < 5 and valor:
            return valor
        valor = descobrir_link(settings)
        app.state.link_cache = (time.monotonic(), valor)
        return valor

    @app.middleware("http")
    async def cabecalhos(request: Request, call_next):
        resp = await call_next(request)
        resp.headers["Cache-Control"] = "no-store"
        resp.headers["X-Content-Type-Options"] = "nosniff"
        resp.headers["Referrer-Policy"] = "no-referrer"
        resp.headers["Content-Security-Policy"] = (
            "default-src 'self'; img-src 'self' data: blob: https://tile.openstreetmap.org; "
            "style-src 'self' 'unsafe-inline'; script-src 'self'; connect-src 'self'; "
            "frame-ancestors 'none'"
        )
        return resp

    @app.get("/", include_in_schema=False)
    def pagina() -> FileResponse:
        return FileResponse(STATIC_DIR / "painel.html", media_type="text/html; charset=utf-8")

    app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")

    @app.get("/api/painel", dependencies=[Depends(exigir_acesso)])
    def painel(limite: int = Query(20, ge=1, le=100), session: Session = Depends(sessao)) -> dict[str, Any]:
        agora = dt.datetime.now(dt.timezone.utc)
        try:
            session.execute(text("SELECT 1"))
            banco = "ok"
        except Exception:  # noqa: BLE001
            return {"servidor": {"banco": "indisponível"}, "gerado_em": agora.isoformat()}
        return {
            "gerado_em": agora.isoformat(),
            "servidor": {
                "banco": banco,
                "segundos_ativo": int(time.monotonic() - iniciado),
                "token_exigido": bool(settings.admin_token),
                "minimo_publico": settings.min_respostas_publicas,
                "minimo_celula": settings.min_respostas_celula,
                "limite_envios_por_min": settings.rate_limit_per_min,
                "tunel": link_atual(),
            },
            "resumo": resumo(session, agora),
            "serie_horaria": serie_horaria(session, agora, 48),
            "recentes": recentes(session, limite),
            "mapa": mapa_admin(session, agora, 72),
        }

    @app.get("/api/qr.svg", dependencies=[Depends(exigir_acesso)])
    def qr() -> Response:
        url = link_atual().get("url")
        if not url:
            raise HTTPException(status_code=404, detail="Ainda não há link público.")
        buf = io.BytesIO()
        segno.make(url, error="m").save(buf, kind="svg", scale=6, border=2, dark="#1B5E20")
        return Response(buf.getvalue(), media_type="image/svg+xml")

    return app


app = create_painel_app()
