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
import datetime as dt
import io
import logging
import secrets
import threading
import time
from collections import defaultdict
from contextlib import asynccontextmanager
from decimal import Decimal
from pathlib import Path
from typing import Iterator

import requests
from fastapi import Depends, FastAPI, Header, HTTPException, Query, Request, Response
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.responses import FileResponse, StreamingResponse
import segno
from fastapi.staticfiles import StaticFiles
from sqlalchemy import Engine, select, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from . import bairros, download_app, exportacao, focos, focos_proximos, publico, qualidade_ar as qar, stats
from .config import Settings
from .db import init_schema, make_engine, make_session_factory
from .models import Resposta, RespostaSintoma
from .ratelimit import RateLimiter
from .schemas import CONTEXTO_CAMPOS, Estatisticas, MapaColetivo, RespostaIn, RespostaOut, coarsen

log = logging.getLogger("alerta.api")

APP_VERSION = "1.10.1"


def create_app(
    settings: Settings | None = None,
    engine: Engine | None = None,
    geocoder: bairros.Geocoder | None = None,
    qualidade_ar: qar.QualidadeAr | None = None,
) -> FastAPI:
    settings = settings or Settings.from_env()
    owns_engine = engine is None
    engine = engine or make_engine(settings.database_url)
    session_factory = make_session_factory(engine)

    parar = threading.Event()

    def preaquecer_focos() -> None:
        """Mantém o cache dos focos quente: a página abre já com dados e o INPE é consultado 1 vez por janela."""
        while not parar.is_set():
            for janela in ("today", "last48h"):
                try:
                    obter_focos(app, janela, "amazonas", [])
                except Exception as exc:  # noqa: BLE001 - segundo plano nunca derruba o servidor
                    log.info("Pré-aquecimento dos focos (%s) falhou: %s", janela, focos.motivo(exc))
            parar.wait(max(60, settings.cache_seconds))

    @asynccontextmanager
    async def lifespan(_: FastAPI):
        init_schema(engine)
        if settings.focos_preaquecer:
            threading.Thread(target=preaquecer_focos, name="focos-preaquecer", daemon=True).start()
        yield
        parar.set()
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

    app.state.publico_cache = {}
    app.state.geocoder = geocoder or (bairros.nominatim(settings, APP_VERSION) if settings.geocoder_ativo else None)
    app.state.bairros_lock = threading.Lock()
    app.state.bairros_thread = None
    app.state.publico_lock = threading.Lock()
    app.state.qualidade_ar = qualidade_ar or (
        qar.QualidadeAr(settings.qualidade_ar_url, settings.qualidade_ar_cache_seconds)
        if settings.qualidade_ar_ativa else None
    )

    register_routes(app)
    _montar_painel_publico(app)
    return app


PUBLICO_DIR = Path(__file__).parent / "static_publico"
VENDOR_DIR = Path(__file__).parent / "static" / "vendor"
#: Segundos em que o resultado do painel público é reaproveitado (protege o banco quando muita
#: gente abre o link ao mesmo tempo).
PUBLICO_CACHE_SEGUNDOS = 10

_CSP_PUBLICO = (
    "default-src 'self'; img-src 'self' data: https://tile.openstreetmap.org https://*.tile.opentopomap.org "
    "https://gibs.earthdata.nasa.gov; "
    "style-src 'self' 'unsafe-inline'; script-src 'self'; connect-src 'self'; "
    "frame-ancestors 'none'; base-uri 'none'"
)


def _montar_painel_publico(app: FastAPI) -> None:
    """Página pública (sem senha) com dados agregados. Ver `app.publico` para as regras."""

    @app.get("/", include_in_schema=False)
    def pagina_publica(request: Request) -> Response:
        h = request.headers
        base = download_app.base_publica(
            request.app.state.settings.public_url, h.get("host", ""), h.get("x-forwarded-proto", ""),
            request.url.scheme, request.url.netloc,
        )
        html = (PUBLICO_DIR / "publico.html").read_text(encoding="utf-8").replace("{{BASE}}", base.rstrip("/"))
        resp = Response(html, media_type="text/html; charset=utf-8")
        resp.headers["Content-Security-Policy"] = _CSP_PUBLICO
        resp.headers["X-Content-Type-Options"] = "nosniff"
        resp.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
        resp.headers["Cache-Control"] = "no-cache"
        return resp

    @app.get("/favicon.ico", include_in_schema=False)
    def favicon() -> FileResponse:
        return FileResponse(PUBLICO_DIR / "favicon.ico", media_type="image/x-icon",
                            headers={"Cache-Control": "public, max-age=86400"})

    app.mount("/assets", StaticFiles(directory=PUBLICO_DIR), name="assets-publicos")
    app.mount("/vendor", StaticFiles(directory=VENDOR_DIR), name="vendor-publico")

    def dados_publicos(request: Request, session: Session, dias: int) -> dict:
        if dias not in publico.PERIODOS:
            raise HTTPException(status_code=422, detail=f"dias deve ser um de {publico.PERIODOS}.")
        st = request.app.state
        with st.publico_lock:
            agora = time.monotonic()
            guardado = st.publico_cache.get(dias)
            if guardado and agora - guardado[0] < PUBLICO_CACHE_SEGUNDOS:
                return guardado[1]
            dados = publico.montar(session, st.settings, dias)
            if dados.get("bairros", {}).get("areas_em_consulta"):
                bairros.disparar_resolucao(request.app)
            st.publico_cache[dias] = (agora, dados)
            return dados

    @app.get("/publico/painel")
    def painel_publico(
        request: Request,
        response: Response,
        dias: int = Query(30),
        session: Session = Depends(get_session),
    ) -> dict:
        dados = dados_publicos(request, session, dias)
        response.headers["Cache-Control"] = f"public, max-age={PUBLICO_CACHE_SEGUNDOS}"
        response.headers["Access-Control-Allow-Origin"] = "*"
        return dados

    # ------------------------------------------------------- qualidade do ar (modelo)

    @app.get("/publico/qualidade-ar")
    def qualidade_do_ar(request: Request, response: Response) -> dict:
        q: qar.QualidadeAr | None = request.app.state.qualidade_ar
        if q is None:
            raise HTTPException(status_code=404, detail="Consulta de qualidade do ar desativada.")
        try:
            dados = q.obter()
        except (requests.RequestException, ValueError) as exc:
            log.warning("Qualidade do ar indisponível: %s", exc.__class__.__name__)
            raise HTTPException(status_code=502, detail="Serviço de qualidade do ar indisponível no momento.")
        response.headers["Cache-Control"] = "public, max-age=60"
        response.headers["Access-Control-Allow-Origin"] = "*"
        return dados

    @app.get("/app/ar")
    def ar_para_o_app(request: Request, response: Response, cod: int = Query(..., ge=1300000, le=1399999)) -> dict:
        """Leitura compacta de UM município, para os alertas do aplicativo (consulta frequente e leve)."""
        q: qar.QualidadeAr | None = request.app.state.qualidade_ar
        if q is None:
            raise HTTPException(status_code=404, detail="Consulta de qualidade do ar desativada.")
        try:
            dados = q.obter()
        except (requests.RequestException, ValueError) as exc:
            log.warning("Qualidade do ar indisponível: %s", exc.__class__.__name__)
            raise HTTPException(status_code=502, detail="Serviço de qualidade do ar indisponível no momento.")
        linha = next((m for m in dados["municipios"] if m["codigo_ibge"] == cod), None)
        if linha is None:
            raise HTTPException(status_code=404, detail="Município do Amazonas não encontrado.")
        response.headers["Cache-Control"] = "public, max-age=60"
        return {
            **linha,
            "estimativa": True,
            "resolucao_km": dados["resolucao_km"],
            "consultado_em": dados["consultado_em"],
            "desatualizado": dados["desatualizado"],
            "escala": dados["escala"],
        }

    @app.get("/app/focos")
    def focos_para_o_app(
        request: Request,
        response: Response,
        cod: int = Query(..., ge=1300000, le=1399999),
        raio_km: int = Query(50),
    ) -> dict:
        """Focos do INPE perto de um município, para os alertas do aplicativo (leve; usa o cache do INPE)."""
        if raio_km not in focos_proximos.RAIOS_KM:
            raise HTTPException(status_code=422, detail=f"raio_km deve ser um de {list(focos_proximos.RAIOS_KM)}.")
        muni = next((m for m in qar.municipios() if m.codigo == cod), None)
        if muni is None:
            raise HTTPException(status_code=404, detail="Município do Amazonas não encontrado.")
        corpo, cache, obtido_em = obter_focos(request.app, "last48h", "amazonas", [])
        resumo = focos_proximos.resumir(corpo, muni.lat, muni.lon, raio_km, dt.datetime.now(dt.timezone.utc))
        response.headers["Cache-Control"] = "public, max-age=60"
        return {
            "codigo_ibge": muni.codigo,
            "municipio": muni.nome,
            **resumo,
            "consultado_em": None if obtido_em is None else obtido_em.astimezone(dt.timezone.utc).isoformat(),
            "desatualizado": cache == "STALE",
            "fonte": "INPE, Programa Queimadas (focos de calor por satélite, estado do Amazonas)",
            "nota": "Foco de calor é detecção por satélite, não incêndio confirmado. Contados só focos registrados no "
                    "Amazonas, a partir da sede do município.",
        }

    # ------------------------------------------------------------- download em CSV

    @app.get("/publico/export.csv")
    def exportar_publico(
        request: Request,
        conjunto: str = Query(...),
        dias: int = Query(30),
        session: Session = Depends(get_session),
    ) -> Response:
        if conjunto not in exportacao.CONJUNTOS:
            raise HTTPException(status_code=422, detail=f"conjunto deve ser um de {list(exportacao.CONJUNTOS)}.")
        agora = dt.datetime.now(dt.timezone.utc)
        if conjunto == "focos":
            body, _, obtido_em = obter_focos(request.app, "last48h", "amazonas", list(focos.SATELLITES))
            conteudo = exportacao.focos(body, obtido_em)
            sufixo = "48h"
        elif conjunto == "qualidade_ar":
            q = request.app.state.qualidade_ar
            if q is None:
                raise HTTPException(status_code=404, detail="Consulta de qualidade do ar desativada.")
            try:
                conteudo = exportacao.qualidade_ar(q.obter())
            except (requests.RequestException, ValueError):
                raise HTTPException(status_code=502, detail="Serviço de qualidade do ar indisponível no momento.")
            sufixo = "atual"
        else:
            dados = dados_publicos(request, session, dias)
            conteudo = getattr(exportacao, conjunto)(dados)
            sufixo = f"{dias}d"
        nome = f"respirar-amazonas_{conjunto}_{sufixo}_{agora:%Y%m%dT%H%MZ}.csv"
        return Response(
            conteudo,
            media_type="text/csv; charset=utf-8",
            headers={
                "Content-Disposition": f'attachment; filename="{nome}"',
                "Cache-Control": "no-store",
                "Access-Control-Allow-Origin": "*",
            },
        )

    # ------------------------------------------------------- download do aplicativo

    @app.get("/publico/app")
    def info_app(request: Request, response: Response) -> dict:
        response.headers["Cache-Control"] = "no-cache"
        return download_app.info(request.app.state.settings.apk_dir)

    def _base(request: Request) -> str:
        h = request.headers
        return download_app.base_publica(
            request.app.state.settings.public_url, h.get("host", ""), h.get("x-forwarded-proto", ""),
            request.url.scheme, request.url.netloc,
        )

    @app.get("/app/versao")
    def versao_app(request: Request, response: Response) -> dict:
        """Consultada pelo aplicativo instalado: há versão nova? É pública e não identifica ninguém."""
        response.headers["Cache-Control"] = "public, max-age=60"
        st = request.app.state.settings
        return download_app.atualizacao_app(st.apk_dir, st.app_versao_minima, _base(request))

    build = download_app.build_site(PUBLICO_DIR, APP_VERSION)

    @app.get("/publico/versao")
    def versao_site(response: Response) -> dict:
        """Consultada pela página aberta: se `build` mudar, ela avisa para recarregar."""
        response.headers["Cache-Control"] = "no-cache"
        return {"build": build, "servidor": APP_VERSION}

    @app.get("/baixar/app.apk")
    def baixar_app(request: Request) -> FileResponse:
        apk_dir = request.app.state.settings.apk_dir
        if not download_app.info(apk_dir)["disponivel"]:
            raise HTTPException(status_code=404, detail="O aplicativo ainda não está disponível para download.")
        return FileResponse(
            download_app.caminho(apk_dir),
            media_type="application/vnd.android.package-archive",
            filename="RespirAR-Amazonas.apk",
            headers={"X-Content-Type-Options": "nosniff", "Cache-Control": "no-cache"},
        )

    @app.get("/publico/qr.svg")
    def qr_publico(request: Request, alvo: str = Query("app", pattern="^(app|site)$")) -> Response:
        """QR code do download do app (ou da própria página). Só texto público: nada identifica ninguém."""
        h = request.headers
        base = download_app.base_publica(
            request.app.state.settings.public_url, h.get("host", ""), h.get("x-forwarded-proto", ""),
            request.url.scheme, request.url.netloc,
        )
        destino = f"{base}/baixar/app.apk" if alvo == "app" else f"{base}/"
        buf = io.BytesIO()
        segno.make(destino, error="m").save(buf, kind="svg", scale=6, border=2, dark="#1B5E20")
        return Response(buf.getvalue(), media_type="image/svg+xml", headers={"Cache-Control": "no-cache"})


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

    @app.get("/bairros")
    def bairros_afetados(
        request: Request,
        dias: int = Query(30, ge=1, le=365),
        session: Session = Depends(get_session),
    ) -> dict:
        """Bairros de Manaus com mais respostas (mínimo por área, como no mapa coletivo)."""
        dados = bairros.ranking(session, request.app.state.settings, dias)
        if dados["areas_em_consulta"]:
            bairros.disparar_resolucao(request.app)
        return dados

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
        body, status, obtido_em = obter_focos(request.app, window, scope, sats)
        return _geojson(body, status, obtido_em)


def obter_focos(app: FastAPI, window: str, scope: str, sats: list[str]) -> tuple[bytes, str, dt.datetime | None]:
    """Resposta do INPE com cache. Devolve (corpo, HIT|MISS|STALE, quando foi obtida).
    Lança HTTPException 502 se o INPE falhar e não houver nada guardado."""
    key = focos.cache_key(window, scope, sats)
    cache: focos.FocosCache = app.state.focos_cache

    fresh = cache.fresh(key)
    if fresh is not None:
        return fresh, "HIT", cache.obtido_em(key)

    with _lock_for(app, key):
        # Outra requisição pode ter preenchido o cache enquanto esperávamos.
        fresh = cache.fresh(key)
        if fresh is not None:
            return fresh, "HIT", cache.obtido_em(key)
        try:
            body = focos.fetch_upstream(window, scope, sats)
        except (requests.RequestException, ValueError) as exc:
            motivo = focos.motivo(exc)
            log.warning("INPE indisponível (%s): %s | %r", key, motivo, str(exc)[:300])
            stale = cache.last_valid(key)
            if stale is not None:
                return stale, "STALE", cache.obtido_em(key)
            raise HTTPException(status_code=502, detail=f"INPE indisponível no momento ({motivo}).")
        cache.store(key, body)
    return body, "MISS", cache.obtido_em(key)


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


def _geojson(body: bytes, cache_status: str, obtido_em: dt.datetime | None = None) -> Response:
    headers = {"X-Cache": cache_status, "Cache-Control": "no-store"}
    if obtido_em is not None:
        # Quando o servidor obteve estes dados do INPE (UTC); o painel público mostra isso.
        headers["X-Consultado-Em"] = obtido_em.astimezone(dt.timezone.utc).isoformat()
    return Response(content=body, media_type="application/json", headers=headers)


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
