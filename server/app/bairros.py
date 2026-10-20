"""Bairros de Manaus mais afetados, a partir das células de ~1 km das respostas.

Como funciona
-------------
1. As respostas guardam a coordenada arredondada (2 casas, ~1,1 km). Cada par (lat, lon) é uma célula.
2. Para as células dentro de Manaus, o nome do bairro vem da geocodificação reversa do
   OpenStreetMap (Nominatim) aplicada ao CENTRO da célula. O resultado fica em cache
   (`celulas_bairro`), então cada célula é consultada uma única vez, a no máximo 1 por segundo
   (política de uso do Nominatim), em uma thread de segundo plano.
3. O ranking soma as respostas por bairro e só mostra bairros com `min_respostas_celula`
   respostas ou mais.

Limite importante: uma célula de ~1 km pode cruzar a divisa de bairros. O bairro atribuído é o
do centro da célula, uma aproximação; os números são estimativas, não contagem por endereço.
"""

from __future__ import annotations

import datetime as dt
import logging
import threading
import time
from decimal import Decimal
from typing import Any, Callable

import requests
from sqlalchemy import case, func, select
from sqlalchemy.orm import Session, sessionmaker

from .config import Settings
from .models import CelulaBairro, Resposta

log = logging.getLogger("alerta.bairros")

#: Caixa que cobre a área urbana de Manaus (lat_min, lon_min, lat_max, lon_max). Só células
#: dentro dela são enviadas ao geocodificador; o município em si é confirmado pelo resultado.
MANAUS_CAIXA = (-3.20, -60.20, -2.90, -59.80)

FONTE = (
    "Bairro obtido do OpenStreetMap (Nominatim) pelo centro de cada área de ~1 km; "
    "aproximação, pois uma área pode cruzar divisas de bairros."
)

#: (lat, lon) -> {"bairro": str | None, "cidade": str | None}, ou None se o serviço falhou.
Geocoder = Callable[[float, float], "dict[str, str | None] | None"]


def em_manaus(lat: float, lon: float) -> bool:
    la0, lo0, la1, lo1 = MANAUS_CAIXA
    return la0 <= lat <= la1 and lo0 <= lon <= lo1


def nominatim(settings: Settings, versao: str = "") -> Geocoder:
    """Geocodificador reverso do Nominatim (ou compatível). `None` em falha de rede/serviço."""
    cabecalho = {"User-Agent": f"RespirAR-Amazonas/{versao or 'dev'} (contato: {settings.geocoder_contato})"}

    def geocodificar(lat: float, lon: float) -> dict[str, str | None] | None:
        try:
            resp = requests.get(
                f"{settings.geocoder_url}/reverse",
                params={"format": "jsonv2", "lat": f"{lat:.5f}", "lon": f"{lon:.5f}", "zoom": 16,
                        "addressdetails": 1, "accept-language": "pt-BR"},
                headers=cabecalho,
                timeout=10,
            )
            resp.raise_for_status()
            endereco = resp.json().get("address") or {}
        except Exception:  # noqa: BLE001 - rede/JSON: tenta de novo numa próxima rodada
            return None
        bairro = (
            endereco.get("suburb") or endereco.get("neighbourhood")
            or endereco.get("city_district") or endereco.get("quarter")
        )
        cidade = endereco.get("city") or endereco.get("town") or endereco.get("municipality")
        return {"bairro": bairro, "cidade": cidade}

    return geocodificar


def _celulas_pendentes(session: Session) -> list[tuple[Decimal, Decimal]]:
    la0, lo0, la1, lo1 = MANAUS_CAIXA
    conhecidas = {(float(a), float(b)) for a, b in session.execute(select(CelulaBairro.lat, CelulaBairro.lon))}
    rows = session.execute(
        select(Resposta.lat, Resposta.lon)
        .where(Resposta.lat.is_not(None), Resposta.lon.is_not(None),
               Resposta.lat.between(la0, la1), Resposta.lon.between(lo0, lo1))
        .group_by(Resposta.lat, Resposta.lon)
    ).all()
    return [(a, b) for a, b in rows if (float(a), float(b)) not in conhecidas]


def resolver_pendentes(
    fabrica: sessionmaker[Session], geocoder: Geocoder, *, limite: int = 40, pausa: float = 1.1
) -> int:
    """Consulta e guarda o bairro das células ainda desconhecidas. Devolve quantas resolveu."""
    with fabrica() as session:
        pendentes = _celulas_pendentes(session)[:limite]
    feitas = 0
    for i, (lat, lon) in enumerate(pendentes):
        if i and pausa:
            time.sleep(pausa)
        achado = geocoder(float(lat), float(lon))
        if achado is None:
            continue  # falha de rede: não grava, tenta depois
        with fabrica() as session:
            session.merge(CelulaBairro(lat=lat, lon=lon, bairro=achado.get("bairro"), cidade=achado.get("cidade")))
            session.commit()
        feitas += 1
    return feitas


def disparar_resolucao(app: Any) -> None:
    """Inicia (se ainda não houver uma rodando) a thread que descobre os bairros pendentes."""
    st = app.state
    if not st.settings.geocoder_ativo or st.geocoder is None:
        return
    with st.bairros_lock:
        t = st.bairros_thread
        if t is not None and t.is_alive():
            return
        st.bairros_thread = threading.Thread(
            target=resolver_pendentes, args=(st.session_factory, st.geocoder), daemon=True, name="bairros"
        )
        st.bairros_thread.start()


def ranking(session: Session, settings: Settings, dias: int, agora: dt.datetime | None = None) -> dict[str, Any]:
    """Bairros de Manaus com mais respostas no período (só os que passam do mínimo por área)."""
    agora = agora or dt.datetime.now(dt.timezone.utc)
    desde = agora - dt.timedelta(days=dias)
    alto = func.sum(case((Resposta.nivel.in_(("high", "emergency")), 1), else_=0))
    rows = session.execute(
        select(Resposta.lat, Resposta.lon, func.count(), alto)
        .where(Resposta.criado_em >= desde, Resposta.lat.is_not(None), Resposta.lon.is_not(None))
        .group_by(Resposta.lat, Resposta.lon)
    ).all()
    nomes = {
        (float(a), float(b)): (bairro, cidade)
        for a, b, bairro, cidade in session.execute(
            select(CelulaBairro.lat, CelulaBairro.lon, CelulaBairro.bairro, CelulaBairro.cidade)
        )
    }
    soma: dict[str, list[int]] = {}
    pendentes = 0
    for lat, lon, qtd, n_alto in rows:
        chave = (float(lat), float(lon))
        if not em_manaus(*chave):
            continue
        if chave not in nomes:
            pendentes += 1
            continue
        bairro, cidade = nomes[chave]
        if not bairro or (cidade or "").strip().lower() != "manaus":
            continue
        acumulado = soma.setdefault(bairro, [0, 0])
        acumulado[0] += int(qtd)
        acumulado[1] += int(n_alto or 0)
    minimo = settings.min_respostas_celula
    lista = [
        {"bairro": b, "respostas": r, "alto_ou_emergencia": a}
        for b, (r, a) in soma.items()
        if r >= minimo
    ]
    lista.sort(key=lambda x: (-x["respostas"], x["bairro"]))
    return {
        "periodo_dias": dias,
        "minimo_por_bairro": minimo,
        "bairros": lista[:15],
        "areas_em_consulta": pendentes,
        "fonte": FONTE,
    }
