"""API do RespirAR Amazonas.

Endpoints
---------
POST /respostas                 registra uma resposta anonimizada do questionário
GET  /estatisticas?dias=30      sintomas mais relatados, níveis de risco e série diária
GET  /mapa?horas=72             áreas com respostas (mapa coletivo; oculta áreas com poucas respostas)
GET  /focos                     focos de calor do INPE (cache); ver app/focos.py
GET  /respostas/export.csv      exportação completa (exige X-Admin-Token)
GET  /health                    verifica a API e a conexão com o banco

Execução local:   uvicorn app.main:app --reload
Com Docker:       docker compose up -d --build   (na raiz do repositório)
"""

from __future__ import annotations

import csv
import io
import logging
import secrets
import threading
from collections import defaultdict
from contextlib import asynccontextmanager
from decimal import Decimal
from typing import Iterator

import requests
from fastapi import Depends, FastAPI, Header, HTTPException, Query, Request, Response
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.responses import StreamingResponse
from sqlalchemy import Engine, select, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from . import focos, stats
from .config import Settings
from .db import init_schema, make_engine, make_session_factory
from .models import Resposta, RespostaSintoma
from .ratelimit import RateLimiter
from .schemas import CONTEXTO_CAMPOS, Estatisticas, MapaColetivo, RespostaIn, RespostaOut, coarsen

log = logging.getLogger("alerta.api")

APP_VERSION = "1.3.1"


def create_app(settings: Settings | None = None, engine: Engine | None = None) -> FastAPI:
    settings = settings or Settings.from_env()
    owns_engine = engine is None
    engine = engine or make_engine(settings.database_url)
    session_factory = make_session_factory(engine)

    @asynccontextmanager
    async def lifespan(_: FastAPI):
        init_schema(engine)
        yield
        if owns_engine:  # um engine injetado (testes) é de quem o criou
            engine.dispose()

    app = FastAPI(
        title="RespirAR Amazonas — API",
        version=APP_VERSION,
        description=(
            "Registro anonimizado de respostas do questionário de sintomas, estatísticas "
            "agregadas e cache dos focos de calor do INPE. Não é um serviço de emergência."
        ),
        lifespan=lifespan,
    )
    app.add_middleware(GZipMiddleware, minimum_size=1024)

    app.state.settings = settings
    app.state.engine = engine
    app.state.session_factory = session_factory
    app.state.limiter = RateLimiter(settings.rate_limit_per_min)
    app.state.focos_cache = focos.FocosCache(settings.cache_seconds, settings.cache_max_entries)
    app.state.focos_locks = defaultdict(threading.Lock)
    app.state.focos_locks_guard = threading.Lock()

    register_routes(app)
    return app


def get_session(request: Request) -> Iterator[Session]:
    with request.app.state.session_factory() as session:
        yield session


def register_routes(app: FastAPI) -> None:
    @app.get("/health")
    def health(session: Session = Depends(get_session)) -> dict[str, str]:
        try:
            session.execute(text("SELECT 1"))
        except Exception as exc:  # noqa: BLE001 - qualquer falha do banco vira 503
            log.error("Falha no banco: %s", exc.__class__.__name__)
            raise HTTPException(status_code=503, detail="Banco de dados indisponível.")
        return {"status": "ok", "version": APP_VERSION}

    # ------------------------------------------------------------------ respostas

    @app.post("/respostas", response_model=RespostaOut, status_code=201)
    def criar_resposta(
        payload: RespostaIn,
        request: Request,
        response: Response,
        session: Session = Depends(get_session),
    ) -> RespostaOut:
        origem = _origem(request)
        if not request.app.state.limiter.allow(origem):
            raise HTTPException(status_code=429, detail="Muitos envios. Tente novamente em instantes.")

        existente = _buscar_por_submission(session, payload)
        if existente is not None:
            response.status_code = 200
            return RespostaOut(id=existente, duplicado=True)

        resposta = Resposta(
            submission_id=payload.submission_id,
            registrado_em=payload.registrado_em,
            # O servidor refaz o arredondamento: coordenada precisa nunca é gravada.
            lat=None if payload.lat is None else Decimal(f"{coarsen(payload.lat):.2f}"),
            lon=None if payload.lon is None else Decimal(f"{coarsen(payload.lon):.2f}"),
            nivel=payload.nivel,
            pontos=payload.pontos,
            exposicao=payload.exposicao,
            idoso=payload.perfil.idoso,
            gestante=payload.perfil.gestante,
            crianca=payload.perfil.crianca,
            doenca_respiratoria=payload.perfil.doenca_respiratoria,
            doenca_cardiaca=payload.perfil.doenca_cardiaca,
            app_version=payload.app_version,
            contexto=(payload.contexto.model_dump(exclude_none=True) or None) if payload.contexto else None,
            sintomas=[
                RespostaSintoma(sintoma=nome, gravidade=gravidade)
                for nome, gravidade in sorted(payload.sintomas.items())
            ],
        )
        session.add(resposta)
        try:
            session.commit()
        except IntegrityError:
            # Corrida: o mesmo envio chegou duas vezes ao mesmo tempo.
            session.rollback()
            existente = _buscar_por_submission(session, payload)
            if existente is None:
                raise
            response.status_code = 200
            return RespostaOut(id=existente, duplicado=True)
        return RespostaOut(id=resposta.id)

    # --------------------------------------------------------------- estatísticas

    @app.get("/estatisticas", response_model=Estatisticas)
    def estatisticas(
        request: Request,
        dias: int = Query(30, ge=1, le=365),
        session: Session = Depends(get_session),
    ) -> Estatisticas:
        return stats.calcular(
            session, dias=dias, minimo=request.app.state.settings.min_respostas_publicas
        )

    @app.get("/mapa", response_model=MapaColetivo)
    def mapa_coletivo(
        request: Request,
        horas: int = Query(72, ge=1, le=24 * 30),
        session: Session = Depends(get_session),
    ) -> MapaColetivo:
        return stats.mapa(
            session, horas=horas, minimo_celula=request.app.state.settings.min_respostas_celula
        )

    # ------------------------------------------------------------------- exportação

    @app.get("/respostas/export.csv")
    def exportar_csv(
        request: Request,
        x_admin_token: str | None = Header(default=None),
    ) -> StreamingResponse:
        esperado = request.app.state.settings.admin_token
        if not esperado:
            raise HTTPException(status_code=404, detail="Exportação desativada.")
        if not x_admin_token or not secrets.compare_digest(x_admin_token, esperado):
            raise HTTPException(status_code=401, detail="Token inválido.")

        # O gerador abre a própria sessão: uma sessão injetada por dependência pode
        # ser fechada antes do fim do streaming, conforme a versão do FastAPI.
        return StreamingResponse(
            _gerar_csv(request.app.state.session_factory),
            media_type="text/csv; charset=utf-8",
            headers={"Content-Disposition": 'attachment; filename="respostas.csv"'},
        )

    # ------------------------------------------------------------------------ focos

    @app.get("/focos")
    def listar_focos(
        request: Request,
        window: str = Query(..., pattern="^(today|last48h)$"),
        scope: str = Query("amazonas", pattern="^(amazonas|brasil)$"),
        satellites: str | None = Query(
            None, description="Lista separada por vírgula. Padrão: todos os conhecidos."
        ),
    ) -> Response:
        sats = _parse_satellites(satellites)
        key = focos.cache_key(window, scope, sats)
        cache: focos.FocosCache = request.app.state.focos_cache

        fresh = cache.fresh(key)
        if fresh is not None:
            return _geojson(fresh, "HIT")

        with _lock_for(request.app, key):
            # Outra requisição pode ter preenchido o cache enquanto esperávamos.
            fresh = cache.fresh(key)
            if fresh is not None:
                return _geojson(fresh, "HIT")
            try:
                body = focos.fetch_upstream(window, scope, sats)
            except (requests.RequestException, ValueError) as exc:
                log.warning("INPE indisponível (%s): %s", key, exc.__class__.__name__)
                stale = cache.last_valid(key)
                if stale is not None:
                    return _geojson(stale, "STALE")
                raise HTTPException(status_code=502, detail="INPE indisponível no momento.")
            cache.store(key, body)
        return _geojson(body, "MISS")


# ---------------------------------------------------------------------- auxiliares


def _origem(request: Request) -> str:
    """Chave do limitador de envios. Atrás do túnel da Cloudflare todas as conexões chegam
    do mesmo endereço interno; com `TRUST_CF_CONNECTING_IP` usa-se o IP real informado por ela.
    O valor existe só em memória (ver ratelimit.py) e nunca é gravado."""
    if request.app.state.settings.trust_cf_connecting_ip:
        real = request.headers.get("cf-connecting-ip", "").strip()
        if real:
            return real[:64]
    return request.client.host if request.client else "desconhecida"


def _buscar_por_submission(session: Session, payload: RespostaIn) -> int | None:
    return session.scalar(
        select(Resposta.id).where(Resposta.submission_id == payload.submission_id)
    )


def _parse_satellites(raw: str | None) -> list[str]:
    if raw is None or not raw.strip():
        return list(focos.SATELLITES)
    sats = [s.strip() for s in raw.split(",") if s.strip()]
    unknown = [s for s in sats if s not in focos.SATELLITES]
    if unknown:
        raise HTTPException(
            status_code=422,
            detail=f"Satélite(s) desconhecido(s): {unknown}. Aceitos: {list(focos.SATELLITES)}",
        )
    return sats


def _lock_for(app: FastAPI, key: str) -> threading.Lock:
    with app.state.focos_locks_guard:
        return app.state.focos_locks[key]


def _geojson(body: bytes, cache_status: str) -> Response:
    return Response(
        content=body,
        media_type="application/json",
        headers={"X-Cache": cache_status, "Cache-Control": "no-store"},
    )


def _celula_ctx(valor: object) -> object:
    """Ausente = vazio (não respondido); booleanos como 1/0."""
    if valor is None:
        return ""
    if isinstance(valor, bool):
        return int(valor)
    return valor


def _gerar_csv(session_factory) -> Iterator[str]:  # noqa: ANN001
    """Gera o CSV em lotes (paginação por id), em formato largo: um sintoma por coluna."""
    with session_factory() as session:
        yield from _linhas_csv(session)


def _linhas_csv(session: Session) -> Iterator[str]:
    sintomas_ids = list(
        session.scalars(
            select(RespostaSintoma.sintoma).distinct().order_by(RespostaSintoma.sintoma)
        )
    )
    colunas = [
        "id", "criado_em", "registrado_em", "lat", "lon", "nivel", "pontos", "exposicao",
        "idoso", "gestante", "crianca", "doenca_respiratoria", "doenca_cardiaca", "app_version",
    ] + [f"ctx_{c}" for c in CONTEXTO_CAMPOS] + [f"sintoma_{s}" for s in sintomas_ids]

    def linha(valores: list[object]) -> str:
        buf = io.StringIO()
        csv.writer(buf, lineterminator="\n").writerow(valores)
        return buf.getvalue()

    yield linha(colunas)
    ultimo_id = 0
    while True:
        lote = session.scalars(
            select(Resposta).where(Resposta.id > ultimo_id).order_by(Resposta.id).limit(1000)
        ).all()
        if not lote:
            return
        for r in lote:
            graus = {s.sintoma: s.gravidade for s in r.sintomas}
            yield linha(
                [
                    r.id, r.criado_em.isoformat(), r.registrado_em.isoformat(),
                    "" if r.lat is None else r.lat, "" if r.lon is None else r.lon,
                    r.nivel, r.pontos, r.exposicao,
                    int(r.idoso), int(r.gestante), int(r.crianca),
                    int(r.doenca_respiratoria), int(r.doenca_cardiaca), r.app_version or "",
                ]
                + [_celula_ctx((r.contexto or {}).get(c)) for c in CONTEXTO_CAMPOS]
                + [graus.get(s, "") for s in sintomas_ids]
            )
        ultimo_id = lote[-1].id
        session.expire_all()  # não acumula o lote anterior na memória


app = create_app()
