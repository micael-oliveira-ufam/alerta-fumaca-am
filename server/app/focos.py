"""Proxy de cache para os focos de calor do INPE (TerraBrasilis, WFS 2.0.0).

Por que existe
--------------
1. Alguns aparelhos/redes não alcançam `terrabrasilis.dpi.inpe.br` (erro "Failed
   host lookup"); o app pode consultar este servidor no lugar.
2. Evita que cada aparelho baixe MB de GeoJSON do INPE: a resposta é guardada em
   memória por alguns minutos e servida (gzip) a todos.
3. Se o INPE falhar, devolve a última resposta válida (cabeçalho `X-Cache: STALE`).

Camadas e campos conferidos no servidor do INPE (GetCapabilities e GetFeature):
- `dados_abertos:focos_hoje_br_todosats` e `dados_abertos:focos_48h_br_todosats`
  (todos os satélites, Brasil). As camadas `*_satref` contêm só o satélite de referência.
- Campo `satelite`. Valores confirmados por contagem (janela de 48 h):
  AQUA_M-T, TERRA_M-T (MODIS), NOAA-20, NOAA-21, NPP-375 e NPP-375D (VIIRS/Suomi-NPP).
- Com `propertyName` sem geometria, o GeoJSON traz `"geometry": null`; por isso
  pedimos `longitude` e `latitude` como propriedades.
"""

from __future__ import annotations

import datetime as dt
import time
from collections import OrderedDict
from typing import Callable, Iterable

import requests

UPSTREAM_URL = "https://terrabrasilis.dpi.inpe.br/queimadas/geoserver/ows"
#: (conexão, leitura). A camada de 48 h do Amazonas pode ter vários MB e o servidor do INPE às vezes demora.
UPSTREAM_TIMEOUT_S = (10, 90)
UPSTREAM_TENTATIVAS = 2
USER_AGENT = "RespirAR-Amazonas/1.0 (UFAM/FCF; painel de saude e queimadas)"

LAYERS = {
    # "Hoje" usa a camada de 48 h; o app recorta o dia local (a camada focos_hoje_* vinha vazia).
    "today": "dados_abertos:focos_48h_br_todosats",
    "last48h": "dados_abertos:focos_48h_br_todosats",
}

#: Satélites aceitos no filtro (lista fechada: o valor entra numa consulta CQL).
SATELLITES = ("AQUA_M-T", "TERRA_M-T", "NOAA-20", "NOAA-21", "NPP-375", "NPP-375D")

#: Estado enfatizado pelo projeto.
STATE = "AMAZONAS"

PROPERTY_NAMES = (
    "longitude,latitude,data_hora_gmt,satelite,municipio,estado,bioma,frp,"
    "risco_fogo,numero_dias_sem_chuva"
)


def build_params(window: str, scope: str, satellites: Iterable[str]) -> dict[str, str]:
    """Parâmetros WFS. `scope` é 'amazonas' ou 'brasil'; satélites já validados."""
    sats = sorted(set(satellites))
    unknown = [s for s in sats if s not in SATELLITES]
    if unknown:
        # Defesa em profundidade: nunca interpolar texto livre em CQL.
        raise ValueError(f"satélite desconhecido: {unknown}")

    filters = []
    if scope == "amazonas":
        filters.append(f"estado='{STATE}'")
    if sats:
        quoted = ",".join(f"'{s}'" for s in sats)
        filters.append(f"satelite IN ({quoted})")

    params = {
        "service": "WFS",
        "version": "2.0.0",
        "request": "GetFeature",
        "typeName": LAYERS[window],
        "outputFormat": "application/json",
        "propertyName": PROPERTY_NAMES,
    }
    if filters:
        params["CQL_FILTER"] = " AND ".join(filters)
    return params


def is_feature_collection(body: bytes) -> bool:
    """Confere se a resposta é um GeoJSON FeatureCollection (e não um erro do WFS)."""
    head = body[:300]
    return head.lstrip().startswith(b"{") and b'"FeatureCollection"' in head


class FocosCache:
    """Cache em memória com TTL, limite de entradas (LRU) e fallback para a última resposta."""

    def __init__(
        self,
        ttl_s: int,
        max_entries: int = 24,
        clock: Callable[[], float] = time.monotonic,
        wall: Callable[[], dt.datetime] = lambda: dt.datetime.now(dt.timezone.utc),
    ) -> None:
        self.ttl_s = ttl_s
        self.max_entries = max_entries
        self._clock = clock
        self._wall = wall
        self._entries: OrderedDict[str, tuple[float, bytes]] = OrderedDict()
        #: Horário (UTC) em que cada resposta foi obtida do INPE: é o "consultado em" mostrado ao público.
        self._obtido_em: dict[str, dt.datetime] = {}

    def fresh(self, key: str) -> bytes | None:
        entry = self._entries.get(key)
        if entry and self._clock() - entry[0] < self.ttl_s:
            self._entries.move_to_end(key)
            return entry[1]
        return None

    def last_valid(self, key: str) -> bytes | None:
        entry = self._entries.get(key)
        return entry[1] if entry else None

    def store(self, key: str, body: bytes) -> None:
        self._entries[key] = (self._clock(), body)
        self._obtido_em[key] = self._wall()
        self._entries.move_to_end(key)
        while len(self._entries) > self.max_entries:
            velha, _ = self._entries.popitem(last=False)  # descarta a mais antiga
            self._obtido_em.pop(velha, None)

    def obtido_em(self, key: str) -> dt.datetime | None:
        """Quando (UTC) a resposta guardada foi obtida do INPE, ou None se não há resposta."""
        return self._obtido_em.get(key)

    def clear(self) -> None:
        self._entries.clear()
        self._obtido_em.clear()

    def __len__(self) -> int:
        return len(self._entries)


def cache_key(window: str, scope: str, satellites: Iterable[str]) -> str:
    return f"{window}|{scope}|{','.join(sorted(set(satellites)))}"


def motivo(exc: BaseException) -> str:
    """Motivo curto e seguro (sem URL nem dados) para mostrar ao público e registrar no log."""
    if isinstance(exc, requests.exceptions.SSLError):
        return "falha de certificado HTTPS"
    if isinstance(exc, requests.exceptions.ConnectTimeout):
        return "tempo esgotado ao conectar"
    if isinstance(exc, requests.exceptions.ReadTimeout):
        return "tempo esgotado esperando resposta"
    if isinstance(exc, requests.exceptions.ConnectionError):
        texto = str(exc).lower()
        if "name resolution" in texto or "nodename" in texto or "getaddrinfo" in texto or "resolve" in texto:
            return "falha de DNS"
        return "sem conexão com o servidor do INPE"
    if isinstance(exc, requests.exceptions.RequestException):
        return "erro de rede"
    if isinstance(exc, ValueError):
        texto = str(exc)
        return f"o INPE respondeu {texto}" if texto.startswith("status ") else "resposta do INPE fora do formato"
    return "erro inesperado"


def fetch_upstream(window: str, scope: str, satellites: Iterable[str]) -> bytes:
    """Consulta o INPE (até `UPSTREAM_TENTATIVAS` vezes em falha de rede ou HTTP 5xx).

    Lança requests.RequestException ou ValueError se a resposta for inválida."""
    params = build_params(window, scope, satellites)
    ultimo: Exception | None = None
    for tentativa in range(UPSTREAM_TENTATIVAS):
        if tentativa:
            time.sleep(2)
        try:
            response = requests.get(
                UPSTREAM_URL, params=params, timeout=UPSTREAM_TIMEOUT_S, headers={"User-Agent": USER_AGENT},
            )
        except requests.RequestException as exc:
            ultimo = exc
            continue
        if response.status_code >= 500:
            ultimo = ValueError(f"status {response.status_code}")
            continue
        if response.status_code != 200:
            raise ValueError(f"status {response.status_code}")
        if not is_feature_collection(response.content):
            raise ValueError("resposta fora do formato GeoJSON")
        return response.content
    assert ultimo is not None
    raise ultimo
