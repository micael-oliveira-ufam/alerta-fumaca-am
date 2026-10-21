"""Qualidade do ar estimada por modelo (Open-Meteo, CAMS) para os 62 municípios do Amazonas.

O QUE É (e o que NÃO é)
-----------------------
- São ESTIMATIVAS DE MODELO (CAMS, Copernicus/ECMWF), não medições de estações. Segundo a
  documentação do Open-Meteo, o modelo global tem resolução de 0,4° (~45 km) e o europeu 0,1°
  (~11 km); para o Amazonas vale o global.
- Com células de ~45 km, **não há como distinguir bairros de Manaus**: toda a área urbana cai
  em uma ou duas células. Por isso este módulo NÃO devolve valores por bairro; devolve um valor
  para Manaus (município) e a ressalva.
- O índice é o US AQI (escala da EPA), o mesmo do app. NÃO é o IQAr oficial brasileiro.
- Uso gratuito do Open-Meteo é só não comercial e exige atribuição ao CAMS (documentação lida
  em 20/10/2026). A cota é protegida por um cache de `qualidade_ar_cache_seconds`.

Formato de resposta: a documentação diz que, com vários locais, o JSON é uma lista na ordem
pedida; a leitura de `current` (`us_aqi`, `pm2_5`, `pm10`, e `time` se vier) é tolerante, e campo
ausente vira `None`: nada é inventado.
"""

from __future__ import annotations

import csv
import datetime as dt
import math
import threading
import time
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import Any, Callable

import requests

CSV_MUNICIPIOS = Path(__file__).parent / "dados" / "municipios_am.csv"
TIMEOUT_S = 25
RESOLUCAO_KM = 45
FONTE = "Open-Meteo Air Quality API (modelo CAMS, Copernicus/ECMWF)"
ATRIBUICAO = "Dados de qualidade do ar: Open-Meteo.com, com dados do CAMS (Copernicus Atmosphere Monitoring Service / ECMWF)."

#: Faixas do US AQI (EPA), as mesmas do app (`airCategoryOf`).
FAIXAS = (
    (50, "boa", "Boa"),
    (100, "moderada", "Moderada"),
    (150, "sensivel", "Ruim para grupos sensíveis"),
    (200, "ruim", "Ruim"),
    (300, "muito_ruim", "Muito ruim"),
    (10**9, "perigosa", "Perigosa"),
)


def categoria(us_aqi: int | None) -> tuple[str | None, str | None]:
    if us_aqi is None:
        return None, None
    for limite, ident, rotulo in FAIXAS:
        if us_aqi <= limite:
            return ident, rotulo
    return None, None  # inalcançável


@dataclass(frozen=True)
class Municipio:
    codigo: int
    nome: str
    lat: float
    lon: float


@lru_cache(maxsize=1)
def municipios() -> tuple[Municipio, ...]:
    with open(CSV_MUNICIPIOS, encoding="utf-8", newline="") as f:
        return tuple(
            Municipio(int(r["codigo_ibge"]), r["nome"], float(r["latitude"]), float(r["longitude"]))
            for r in csv.DictReader(f)
        )


def montar_params(munis: tuple[Municipio, ...]) -> dict[str, str]:
    return {
        "latitude": ",".join(f"{m.lat:.4f}" for m in munis),
        "longitude": ",".join(f"{m.lon:.4f}" for m in munis),
        "current": "us_aqi,pm2_5,pm10",
        "timezone": "GMT",
    }


def _num(valor: Any) -> float | None:
    if isinstance(valor, bool) or not isinstance(valor, (int, float)):
        return None
    if not math.isfinite(valor) or valor < 0:
        return None
    return float(valor)


def _instante(valor: Any) -> str | None:
    """`time` do Open-Meteo vem sem fuso ("2026-10-20T14:15") e, com timezone=GMT, é UTC."""
    if not isinstance(valor, str) or not valor.strip():
        return None
    texto = valor.strip()
    if not (texto.endswith("Z") or "+" in texto[10:] or "-" in texto[10:]):
        texto += "Z"
    try:
        dt.datetime.fromisoformat(texto.replace("Z", "+00:00"))
    except ValueError:
        return None
    return texto


def interpretar(corpo: Any, munis: tuple[Municipio, ...]) -> list[dict[str, Any]]:
    """Converte a resposta do Open-Meteo em uma linha por município. Lança ValueError se inválida."""
    if isinstance(corpo, dict):
        if corpo.get("error"):
            raise ValueError(f"serviço recusou a consulta: {corpo.get('reason', 'motivo não informado')}")
        itens = [corpo]
    elif isinstance(corpo, list):
        itens = corpo
    else:
        raise ValueError("resposta em formato inesperado")
    if len(itens) != len(munis):
        raise ValueError(f"a resposta tem {len(itens)} local(is), mas foram pedidos {len(munis)}")

    linhas = []
    for m, item in zip(munis, itens):
        atual = item.get("current") if isinstance(item, dict) else None
        atual = atual if isinstance(atual, dict) else {}
        aqi = _num(atual.get("us_aqi"))
        aqi = None if aqi is None else int(round(aqi))
        pm25, pm10 = _num(atual.get("pm2_5")), _num(atual.get("pm10"))
        cat_id, cat_rotulo = categoria(aqi)
        linhas.append({
            "codigo_ibge": m.codigo,
            "municipio": m.nome,
            "latitude": m.lat,
            "longitude": m.lon,
            "us_aqi": aqi,
            "categoria": cat_id,
            "categoria_rotulo": cat_rotulo,
            "pm2_5": None if pm25 is None else round(pm25, 1),
            "pm10": None if pm10 is None else round(pm10, 1),
            # Parte fina do particulado inalável (PM2,5 ÷ PM10), só se ambos existirem e PM10 > 0.
            "fracao_fina_pct": round(100 * pm25 / pm10) if pm25 is not None and pm10 else None,
            "referencia_modelo": _instante(atual.get("time")),
        })
    return linhas


def resumir(linhas: list[dict[str, Any]]) -> dict[str, Any]:
    com_aqi = [x for x in linhas if x["us_aqi"] is not None]
    com_pm = [x for x in linhas if x["pm2_5"] is not None]
    pior = max(com_aqi, key=lambda x: x["us_aqi"], default=None)
    pm_max = max(com_pm, key=lambda x: x["pm2_5"], default=None)
    return {
        "total": len(linhas),
        "com_dado": len(com_aqi),
        "pior": None if pior is None else {"municipio": pior["municipio"], "us_aqi": pior["us_aqi"], "categoria_rotulo": pior["categoria_rotulo"]},
        "pm2_5_max": None if pm_max is None else {"municipio": pm_max["municipio"], "pm2_5": pm_max["pm2_5"]},
        "por_categoria": {
            ident: sum(1 for x in com_aqi if x["categoria"] == ident) for _, ident, _ in FAIXAS
        },
    }


class QualidadeAr:
    """Consulta com cache (TTL) e devolução da última resposta boa se o serviço falhar."""

    def __init__(
        self,
        url: str,
        ttl_s: int,
        clock: Callable[[], float] = time.monotonic,
        agora: Callable[[], dt.datetime] = lambda: dt.datetime.now(dt.timezone.utc),
        http_get: Callable[..., Any] = requests.get,
    ) -> None:
        self.url, self.ttl_s = url, ttl_s
        self._clock, self._agora, self._http_get = clock, agora, http_get
        self._guardado: tuple[float, dict[str, Any]] | None = None
        self._lock = threading.Lock()

    def obter(self) -> dict[str, Any]:
        with self._lock:
            if self._guardado and self._clock() - self._guardado[0] < self.ttl_s:
                return {**self._guardado[1], "desatualizado": False}
            try:
                dados = self._consultar()
            except (requests.RequestException, ValueError):
                if self._guardado:  # serviço fora do ar: devolve a última resposta boa, marcada
                    return {**self._guardado[1], "desatualizado": True}
                raise
            self._guardado = (self._clock(), dados)
            return {**dados, "desatualizado": False}

    def _consultar(self) -> dict[str, Any]:
        munis = municipios()
        resp = self._http_get(
            self.url, params=montar_params(munis), timeout=TIMEOUT_S,
            headers={"User-Agent": "RespirAR-Amazonas (UFAM/FCF)"},
        )
        if resp.status_code != 200:
            raise ValueError(f"status {resp.status_code}")
        linhas = interpretar(resp.json(), munis)
        refs = [x["referencia_modelo"] for x in linhas if x["referencia_modelo"]]
        manaus = next((x for x in linhas if x["municipio"] == "Manaus"), None)
        return {
            "fonte": FONTE,
            "atribuicao": ATRIBUICAO,
            "estimativa": True,
            "resolucao_km": RESOLUCAO_KM,
            "escala": "US AQI (EPA); não é o IQAr oficial brasileiro",
            "consultado_em": self._agora().isoformat(),
            "referencia_modelo": max(refs) if refs else None,
            "municipios": linhas,
            "manaus": manaus,
            "resumo": resumir(linhas),
            "faixas": [{"ate": None if lim >= 10**9 else lim, "id": i, "rotulo": r} for lim, i, r in FAIXAS],
            "nota_bairros": (
                f"O modelo tem células de ~{RESOLUCAO_KM} km: o valor de Manaus vale para toda a área urbana "
                "e não distingue bairros."
            ),
        }
