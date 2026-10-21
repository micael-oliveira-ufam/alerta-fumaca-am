"""Segunda fonte de focos de calor: NASA FIRMS (Fire Information for Resource Management System).

Por que existe: ter mais de uma fonte. Se o INPE não responder, o painel e os alertas continuam com dados
da NASA, e a página deixa claro de onde vêm. A pessoa também pode escolher a fonte na página.

Verificado ao vivo em 20/10/2026 (consulta com a chave do projeto, 2 dias, caixa do Amazonas):
- URL `https://firms.modaps.eosdis.nasa.gov/api/area/csv/<MAP_KEY>/<FONTE>/<oeste,sul,leste,norte>/<dias 1-5>`;
- cabeçalho VIIRS: latitude,longitude,bright_ti4,scan,track,acq_date,acq_time,satellite,instrument,confidence,
  version,bright_ti5,frp,daynight (a coluna `acq_time` é HHMM em UTC, sem zeros à esquerda: `516` = 05:16);
- cabeçalho MODIS: latitude,longitude,brightness,scan,track,acq_date,acq_time,satellite,instrument,confidence,
  version,bright_t31,frp,daynight (satellite = Terra ou Aqua).
Não verificado: termos de uso/atribuição da NASA (as páginas lidas não os trazem) e a caixa abaixo.

Limites declarados ao público:
- o FIRMS filtra por CAIXA geográfica, não por estado: entram focos de pedaços de estados vizinhos e não há município;
- algoritmos e satélites diferem dos do INPE; as contagens não são comparáveis.

A chave vai na URL: nunca deve aparecer em log nem em mensagem de erro (ver `FirmsErro`).
"""

from __future__ import annotations

import csv
import datetime as dt
import io
import json
import time
from typing import Any, Callable

import requests

BASE_URL = "https://firms.modaps.eosdis.nasa.gov/api/area/csv"
#: Extremos aproximados do Amazonas (2°15'N a 9°49'S; 73°48'W a 56°06'W). Conferir contra o limite oficial do IBGE.
CAIXA_AMAZONAS = (-73.8, -9.85, -56.1, 2.25)  # oeste, sul, leste, norte
FONTES = ("VIIRS_SNPP_NRT", "VIIRS_NOAA20_NRT", "VIIRS_NOAA21_NRT", "MODIS_NRT")
#: Mesmos identificadores do INPE, para a página reaproveitar rótulos e tabelas.
SATELITE_DA_FONTE = {"VIIRS_SNPP_NRT": "NPP-375", "VIIRS_NOAA20_NRT": "NOAA-20", "VIIRS_NOAA21_NRT": "NOAA-21"}
SATELITE_MODIS = {"terra": "TERRA_M-T", "aqua": "AQUA_M-T"}
TIMEOUT_S = (10, 60)
TENTATIVAS = 2
USER_AGENT = "RespirAR-Amazonas/1.0 (UFAM/FCF; painel de saude e queimadas)"
FONTE_ROTULO = "NASA FIRMS"


class FirmsErro(Exception):
    """Falha ao consultar o FIRMS. A mensagem é segura (sem URL, sem chave)."""

    def __init__(self, motivo_publico: str) -> None:
        super().__init__(motivo_publico)
        self.motivo_publico = motivo_publico


def _instante(data: str, hhmm: str) -> dt.datetime | None:
    try:
        n = int(str(hhmm).strip())
        return dt.datetime.strptime(data.strip(), "%Y-%m-%d").replace(
            hour=n // 100, minute=n % 100, tzinfo=dt.timezone.utc)
    except (ValueError, TypeError):
        return None


def _num(v: Any) -> float | None:
    try:
        x = float(v)
    except (TypeError, ValueError):
        return None
    return x if x == x else None  # descarta NaN


def converter(csv_texto: str, fonte: str, agora: dt.datetime, horas: int = 48) -> list[dict[str, Any]]:
    """CSV do FIRMS -> propriedades no mesmo formato do INPE. Linhas inválidas ou fora da janela são ignoradas."""
    if not csv_texto.lstrip().lower().startswith("latitude"):
        raise FirmsErro("resposta do FIRMS fora do formato")
    ini = agora - dt.timedelta(hours=horas)
    feicoes = []
    for linha in csv.DictReader(io.StringIO(csv_texto)):
        lat, lon = _num(linha.get("latitude")), _num(linha.get("longitude"))
        t = _instante(linha.get("acq_date") or "", linha.get("acq_time") or "")
        if lat is None or lon is None or t is None or t < ini or t > agora + dt.timedelta(minutes=10):
            continue
        if fonte == "MODIS_NRT":
            sat = SATELITE_MODIS.get(str(linha.get("satellite", "")).strip().lower())
        else:
            sat = SATELITE_DA_FONTE.get(fonte)
        if sat is None:
            continue
        feicoes.append({
            "type": "Feature", "geometry": None,
            "properties": {
                "data_hora_gmt": t.strftime("%Y-%m-%d %H:%M:%S"), "satelite": sat, "municipio": None, "estado": None,
                "bioma": None, "latitude": lat, "longitude": lon, "frp": _num(linha.get("frp")),
                "risco_fogo": None, "numero_dias_sem_chuva": None, "fonte": FONTE_ROTULO,
            },
        })
    return feicoes


def _baixar(chave: str, fonte: str, dias: int, http_get: Callable[..., Any]) -> str:
    oeste, sul, leste, norte = CAIXA_AMAZONAS
    url = f"{BASE_URL}/{chave}/{fonte}/{oeste},{sul},{leste},{norte}/{dias}"
    ultimo = "erro de rede"
    for tentativa in range(TENTATIVAS):
        if tentativa:
            time.sleep(2)
        try:
            r = http_get(url, timeout=TIMEOUT_S, headers={"User-Agent": USER_AGENT})
        except requests.exceptions.Timeout:
            ultimo = "tempo esgotado"
            continue
        except requests.exceptions.SSLError:
            ultimo = "falha de certificado HTTPS"
            continue
        except requests.RequestException:
            ultimo = "sem conexão com o FIRMS"
            continue
        if r.status_code >= 500:
            ultimo = f"o FIRMS respondeu {r.status_code}"
            continue
        if r.status_code in (401, 403):
            raise FirmsErro("chave do FIRMS recusada")
        if r.status_code != 200:
            raise FirmsErro(f"o FIRMS respondeu {r.status_code}")
        return r.text
    raise FirmsErro(ultimo)


def fetch_geojson(
    chave: str, satelites: list[str] | None = None, agora: dt.datetime | None = None,
    http_get: Callable[..., Any] = requests.get, dias: int = 2,
) -> bytes:
    """GeoJSON (FeatureCollection) com os focos das últimas 48 h na caixa do Amazonas.

    Consulta as 4 fontes; se ALGUMA responder, usa o que obteve. Só falha se nenhuma responder."""
    if not chave:
        raise FirmsErro("chave do FIRMS não configurada")
    agora = (agora or dt.datetime.now(dt.timezone.utc)).astimezone(dt.timezone.utc)
    feicoes: list[dict[str, Any]] = []
    falhas: list[str] = []
    for fonte in FONTES:
        try:
            feicoes += converter(_baixar(chave, fonte, dias, http_get), fonte, agora)
        except FirmsErro as exc:
            if "chave" in exc.motivo_publico:
                raise
            falhas.append(exc.motivo_publico)
    if len(falhas) == len(FONTES):
        raise FirmsErro(falhas[0])
    if satelites:
        feicoes = [f for f in feicoes if f["properties"]["satelite"] in satelites]
    return json.dumps({"type": "FeatureCollection", "features": feicoes}, ensure_ascii=False).encode("utf-8")
