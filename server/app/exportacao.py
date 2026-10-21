"""Exportação em CSV dos dados PÚBLICOS do painel (agregados). Nada individual sai daqui.

Cada conjunto é montado a partir do MESMO dicionário que alimenta o painel público
(`publico.montar`), então as regras de privacidade (mínimo de respostas, contagens pequenas
ocultas, áreas e bairros só com respostas suficientes) valem igualmente nos arquivos.
Abaixo do mínimo, o arquivo traz só o cabeçalho.

Formato: UTF-8 com BOM (o Excel abre os acentos certo), separador vírgula, quebra de linha `\\n`,
ponto como separador decimal, datas em ISO 8601. Texto que começa com `= + - @` ganha um `'`
na frente, para não virar fórmula ao abrir em planilha (o nome de bairro vem de fonte externa).
"""

from __future__ import annotations

import csv
import datetime as dt
import io
import json
from typing import Any, Iterable

MANAUS_UTC = dt.timezone(dt.timedelta(hours=-4))
NIVEL_ROTULO = {"low": "Baixo", "moderate": "Moderado", "high": "Alto", "emergency": "Procure atendimento"}

#: conjunto -> (descrição para a página, usa o período?)
CONJUNTOS: dict[str, tuple[str, bool]] = {
    "sintomas": ("Sintomas relatados (leve, moderado, intenso)", True),
    "niveis": ("Nível de risco calculado pelo app", True),
    "serie_diaria": ("Respostas por dia", True),
    "bairros": ("Bairros de Manaus com respostas suficientes", True),
    "areas": ("Áreas de ~1 km do mapa coletivo", True),
    "perfil_contexto": ("Perfil, exposição e situação de quem respondeu", True),
    "focos": ("Focos de calor do INPE (últimas 48 h, Amazonas)", False),
    "qualidade_ar": ("Qualidade do ar estimada por município (modelo CAMS)", False),
}


def _seguro(valor: Any) -> Any:
    if isinstance(valor, str) and valor[:1] in ("=", "+", "-", "@", "\t", "\r"):
        return "'" + valor
    return valor


def serializar(colunas: list[str], linhas: Iterable[Iterable[Any]]) -> bytes:
    buf = io.StringIO()
    w = csv.writer(buf, lineterminator="\n")
    w.writerow(colunas)
    for linha in linhas:
        w.writerow(["" if v is None else _seguro(v) for v in linha])
    return ("﻿" + buf.getvalue()).encode("utf-8")


def _meta(d: dict[str, Any]) -> list[Any]:
    return [d.get("periodo_dias"), d.get("gerado_em")]


_META_COLS = ["periodo_dias", "gerado_em_utc"]


def sintomas(d: dict[str, Any]) -> bytes:
    cols = _META_COLS + ["sintoma_id", "sintoma", "relatos", "percentual_das_respostas", "leve", "moderado", "intenso", "gravidade_media_0a3"]
    linhas = [
        _meta(d) + [s["id"], s["rotulo"], s["relatos"], s["percentual"], s["leve"], s["moderado"], s["intenso"], s["gravidade_media"]]
        for s in d.get("sintomas", [])
    ]
    return serializar(cols, linhas)


def niveis(d: dict[str, Any]) -> bytes:
    cols = _META_COLS + ["nivel_id", "nivel", "respostas"]
    linhas = [_meta(d) + [k, NIVEL_ROTULO.get(k, k), v] for k, v in (d.get("niveis") or {}).items()]
    return serializar(cols, linhas)


def serie_diaria(d: dict[str, Any]) -> bytes:
    cols = _META_COLS + ["dia_utc", "respostas"]
    return serializar(cols, [_meta(d) + [x["dia"], x["respostas"]] for x in d.get("serie_diaria", [])])


def bairros(d: dict[str, Any]) -> bytes:
    cols = _META_COLS + ["bairro", "respostas", "respostas_nivel_alto_ou_emergencia"]
    b = (d.get("bairros") or {}).get("bairros", [])
    return serializar(cols, [_meta(d) + [x["bairro"], x["respostas"], x["alto_ou_emergencia"]] for x in b])


def areas(d: dict[str, Any]) -> bytes:
    cols = _META_COLS + ["lat_aprox_1km", "lon_aprox_1km", "respostas", "pior_nivel_id", "pior_nivel"]
    c = (d.get("mapa") or {}).get("celulas", [])
    return serializar(cols, [_meta(d) + [x["lat"], x["lon"], x["respostas"], x["pior_nivel"], NIVEL_ROTULO.get(x["pior_nivel"], "")] for x in c])


def perfil_contexto(d: dict[str, Any]) -> bytes:
    """Formato longo (grupo, categoria, respostas). Contagem pequena fica vazia (oculta)."""
    cols = _META_COLS + ["grupo", "categoria", "respostas"]
    linhas: list[list[Any]] = []
    for k, v in (d.get("perfil") or {}).items():
        linhas.append(_meta(d) + ["perfil", k, v])
    for k, v in (d.get("exposicao") or {}).items():
        linhas.append(_meta(d) + ["exposicao", k, v])
    for campo, info in (d.get("contexto") or {}).items():
        linhas.append(_meta(d) + [f"contexto:{campo}", "(total que respondeu)", info["respondeu"]])
        for k, v in info["valores"].items():
            linhas.append(_meta(d) + [f"contexto:{campo}", k, v])
    return serializar(cols, linhas)


def _utc(valor: Any) -> dt.datetime | None:
    texto = str(valor or "").strip().replace(" ", "T")
    if not texto:
        return None
    if not (texto.endswith("Z") or "+" in texto[10:] or "-" in texto[10:]):
        texto += "Z"  # o INPE entrega data_hora_gmt em UTC, às vezes sem o "Z"
    try:
        return dt.datetime.fromisoformat(texto.replace("Z", "+00:00"))
    except ValueError:
        return None


def focos(geojson: bytes, consultado_em: dt.datetime | None) -> bytes:
    """Detecções do INPE como estão no GeoJSON, mais o horário de Manaus e o instante da consulta."""
    cols = [
        "data_hora_utc", "data_hora_manaus", "satelite", "municipio", "estado", "bioma", "latitude", "longitude",
        "frp_mw", "risco_fogo", "dias_sem_chuva", "consultado_em_utc",
    ]
    consulta = None if consultado_em is None else consultado_em.astimezone(dt.timezone.utc).isoformat()
    linhas = []
    for f in json.loads(geojson).get("features", []):
        p = f.get("properties") or {}
        lat, lon = p.get("latitude"), p.get("longitude")
        coords = (f.get("geometry") or {}).get("coordinates")
        if (lat is None or lon is None) and coords:
            lon, lat = coords[0], coords[1]
        t = _utc(p.get("data_hora_gmt"))
        linhas.append([
            None if t is None else t.astimezone(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            None if t is None else t.astimezone(MANAUS_UTC).strftime("%Y-%m-%dT%H:%M:%S-04:00"),
            p.get("satelite"), p.get("municipio"), p.get("estado"), p.get("bioma"), lat, lon,
            p.get("frp"), p.get("risco_fogo"), p.get("numero_dias_sem_chuva"), consulta,
        ])
    linhas.sort(key=lambda x: x[0] or "", reverse=True)
    return serializar(cols, linhas)


def qualidade_ar(q: dict[str, Any]) -> bytes:
    cols = [
        "codigo_ibge", "municipio", "latitude", "longitude", "us_aqi", "categoria", "pm2_5_ugm3", "pm10_ugm3",
        "fracao_fina_pm2_5_sobre_pm10_pct", "referencia_modelo_utc", "consultado_em_utc", "resolucao_modelo_km", "fonte",
    ]
    linhas = [
        [m["codigo_ibge"], m["municipio"], m["latitude"], m["longitude"], m["us_aqi"], m["categoria_rotulo"], m["pm2_5"], m["pm10"],
         m["fracao_fina_pct"], m["referencia_modelo"], q["consultado_em"], q["resolucao_km"], q["fonte"]]
        for m in q["municipios"]
    ]
    return serializar(cols, linhas)
