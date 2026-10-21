"""Terceira via dos focos de calor: arquivos CSV dos "Dados Abertos" do INPE (Programa Queimadas).

Por que existe: em 20/10/2026 o endereço WFS antigo do TerraBrasilis (`/queimadas/geoserver/ows`) passou a responder
404 no servidor do usuário e o novo não foi encontrado. Os arquivos diários, porém, continuam publicados em
`https://dataserver-coids.inpe.br/queimadas/queimadas/focos/csv/diario/Brasil/focos_diario_br_AAAAMMDD.csv`
(listagem lida em 20/10/2026: arquivos de 11 a 20/10, um por dia UTC; o do dia corrente é parcial).

Cabeçalho observado em 20/10/2026 (lido pelo agente, não baixado por `curl`):
id, lat, lon, data_hora_gmt, satelite, municipio, estado, pais, municipio_id, estado_id, pais_id,
numero_dias_sem_chuva, precipitacao, risco_fogo, bioma, frp  (data_hora_gmt = "AAAA-MM-DD HH:MM:SS", UTC).
Não verificado: o separador exato (o código aceita `,` e `;`) e a grafia de `estado` (comparado sem acento e sem
diferenciar maiúsculas) e de `satelite` (usa-se o texto como vem, igual ao WFS: NOAA-20, NPP-375, AQUA_M-T...).

Saída: mesmo GeoJSON do WFS (`geometry: null`, `latitude`/`longitude` nas propriedades, `estado` em MAIÚSCULAS),
para o app e o painel não precisarem mudar.
"""

from __future__ import annotations

import csv
import datetime as dt
import json
import time
import unicodedata
from typing import Any, Callable, Iterable

import requests

BASE_URL = "https://dataserver-coids.inpe.br/queimadas/queimadas/focos/csv/diario/Brasil"
TIMEOUT_S = (10, 60)
TAMANHO_MAX = 60 * 1024 * 1024
USER_AGENT = "RespirAR-Amazonas/1.0 (UFAM/FCF; painel de saude e queimadas)"
FONTE_ROTULO = "INPE (dados abertos, CSV)"


#: Arquivos já baixados (url -> (instante, linhas)), por 5 min: as várias combinações de satélites/janelas
#: pedidas pelo app e pelo pré-aquecimento reaproveitam o mesmo download. Só vale para o `requests.get` real.
_CACHE: dict[str, tuple[float, list[str]]] = {}
CACHE_S = 300


class CsvInpeErro(Exception):
    """Falha ao obter os CSV do INPE. A mensagem é segura para mostrar ao público."""

    def __init__(self, motivo_publico: str) -> None:
        super().__init__(motivo_publico)
        self.motivo_publico = motivo_publico


def url_do_dia(dia: dt.date) -> str:
    return f"{BASE_URL}/focos_diario_br_{dia:%Y%m%d}.csv"


def _sem_acento(texto: str) -> str:
    return "".join(c for c in unicodedata.normalize("NFD", texto) if unicodedata.category(c) != "Mn").upper().strip()


def _num(v: Any) -> float | None:
    try:
        x = float(str(v).strip().replace(",", "."))
    except (TypeError, ValueError):
        return None
    return x if x == x else None


def _instante(texto: str) -> dt.datetime | None:
    t = (texto or "").strip().replace("T", " ").rstrip("Z")
    for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M:%S.%f", "%Y-%m-%d %H:%M"):
        try:
            return dt.datetime.strptime(t, fmt).replace(tzinfo=dt.timezone.utc)
        except ValueError:
            continue
    return None


def converter(
    linhas: Iterable[str], agora: dt.datetime, horas: int = 48, amazonas: bool = True,
    satelites: Iterable[str] | None = None,
) -> list[dict[str, Any]]:
    """Linhas de texto de um CSV -> feições. Linhas inválidas ou fora da janela/filtro são ignoradas."""
    it = iter(linhas)
    try:
        cab = next(it)
    except StopIteration as exc:
        raise CsvInpeErro("arquivo do INPE vazio") from exc
    cab = cab.lstrip("﻿")
    delim = ";" if cab.count(";") > cab.count(",") else ","
    nomes = [n.strip().strip('"').lower() for n in next(csv.reader([cab], delimiter=delim))]
    if "lat" not in nomes or "lon" not in nomes or "data_hora_gmt" not in nomes:
        raise CsvInpeErro("arquivo do INPE fora do formato esperado")
    ini = agora - dt.timedelta(hours=horas)
    fim = agora + dt.timedelta(minutes=10)
    aceitos = set(satelites) if satelites else None
    feicoes: list[dict[str, Any]] = []
    for campos in csv.reader(it, delimiter=delim):
        if len(campos) < len(nomes):
            continue
        linha = dict(zip(nomes, campos))
        estado = _sem_acento(linha.get("estado", ""))
        if amazonas and estado != "AMAZONAS":
            continue
        sat = (linha.get("satelite") or "").strip()
        if aceitos is not None and sat not in aceitos:
            continue
        lat, lon = _num(linha.get("lat")), _num(linha.get("lon"))
        t = _instante(linha.get("data_hora_gmt", ""))
        if lat is None or lon is None or t is None or t < ini or t > fim:
            continue
        dias = _num(linha.get("numero_dias_sem_chuva"))
        feicoes.append({
            "type": "Feature", "geometry": None,
            "properties": {
                "data_hora_gmt": t.strftime("%Y-%m-%dT%H:%M:%SZ"), "satelite": sat,
                "municipio": (linha.get("municipio") or "").strip().upper(), "estado": estado,
                "bioma": (linha.get("bioma") or "").strip(), "latitude": lat, "longitude": lon,
                "frp": _num(linha.get("frp")), "risco_fogo": _num(linha.get("risco_fogo")),
                "numero_dias_sem_chuva": int(dias) if dias is not None else None, "fonte": FONTE_ROTULO,
            },
        })
    return feicoes


def _baixar_dia(dia: dt.date, http_get: Callable[..., Any]) -> list[str] | None:
    """Linhas do CSV do dia; None se o arquivo ainda não existe (404). Lança CsvInpeErro nas demais falhas."""
    usa_cache = http_get is requests.get
    url = url_do_dia(dia)
    if usa_cache:
        guardado = _CACHE.get(url)
        if guardado and time.monotonic() - guardado[0] < CACHE_S:
            return guardado[1]
    linhas = _baixar_dia_sem_cache(dia, http_get)
    if usa_cache and linhas is not None:
        if len(_CACHE) >= 6:
            _CACHE.pop(min(_CACHE, key=lambda k: _CACHE[k][0]))
        _CACHE[url] = (time.monotonic(), linhas)
    return linhas


def _baixar_dia_sem_cache(dia: dt.date, http_get: Callable[..., Any]) -> list[str] | None:
    try:
        r = http_get(url_do_dia(dia), timeout=TIMEOUT_S, headers={"User-Agent": USER_AGENT}, stream=True)
    except requests.exceptions.Timeout as exc:
        raise CsvInpeErro("tempo esgotado") from exc
    except requests.exceptions.SSLError as exc:
        raise CsvInpeErro("falha de certificado HTTPS") from exc
    except requests.RequestException as exc:
        raise CsvInpeErro("sem conexão com o INPE") from exc
    try:
        if r.status_code == 404:
            return None
        if r.status_code != 200:
            raise CsvInpeErro(f"o INPE respondeu {r.status_code}")
        total = 0
        linhas: list[str] = []
        try:
            for bruta in r.iter_lines(decode_unicode=False):
                total += len(bruta) + 1
                if total > TAMANHO_MAX:
                    raise CsvInpeErro("arquivo do INPE grande demais")
                linhas.append(bruta.decode("utf-8", errors="replace"))
        except requests.RequestException as exc:
            raise CsvInpeErro("conexão interrompida") from exc
        return linhas
    finally:
        r.close()


def fetch_geojson(
    scope: str, satelites: Iterable[str] | None = None, agora: dt.datetime | None = None,
    http_get: Callable[..., Any] = requests.get, horas: int = 48,
) -> bytes:
    """GeoJSON com os focos das últimas `horas` h a partir dos CSV diários (dia UTC corrente e anteriores).

    Se ALGUM dia responder, usa o que obteve; só falha se nenhum arquivo puder ser lido."""
    agora = (agora or dt.datetime.now(dt.timezone.utc)).astimezone(dt.timezone.utc)
    dias = [(agora - dt.timedelta(days=n)).date() for n in range(horas // 24 + 1)]
    feicoes: list[dict[str, Any]] = []
    lidos, ultimo = 0, "nenhum arquivo disponível"
    for dia in dias:
        try:
            linhas = _baixar_dia(dia, http_get)
        except CsvInpeErro as exc:
            ultimo = exc.motivo_publico
            continue
        if linhas is None:
            continue
        lidos += 1
        feicoes += converter(linhas, agora, horas=horas, amazonas=(scope == "amazonas"), satelites=satelites)
    if lidos == 0:
        raise CsvInpeErro(ultimo)
    feicoes.sort(key=lambda f: f["properties"]["data_hora_gmt"])
    return json.dumps({"type": "FeatureCollection", "features": feicoes}, ensure_ascii=False).encode("utf-8")
