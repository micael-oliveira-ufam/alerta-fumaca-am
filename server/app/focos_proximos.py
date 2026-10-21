"""Focos de calor perto de um município, para os alertas do aplicativo.

Usa o mesmo GeoJSON em cache do INPE (camada de 48 h, estado do Amazonas). Conta as detecções
dentro de um raio ao redor da SEDE do município (coordenada de `dados/municipios_am.csv`).

Limites (declarados também na resposta e no app):
- só entram detecções registradas no estado do Amazonas (a consulta ao INPE é filtrada por estado);
  focos logo do outro lado de uma divisa não são contados;
- foco de calor não é incêndio confirmado: é a detecção de calor por satélite (pode ser queimada
  controlada, por exemplo) e depende da passagem e das nuvens;
- o raio é medido a partir da sede, não da área urbana nem do limite do município.
"""

from __future__ import annotations

import datetime as dt
import json
import math
from typing import Any

RAIOS_KM = (10, 25, 50, 100)
_R_TERRA_KM = 6371.0088


def distancia_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Distância na esfera (haversine). Erro de até ~0,5% frente ao elipsoide: irrelevante para alertas."""
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = p2 - p1, math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * _R_TERRA_KM * math.asin(min(1.0, math.sqrt(a)))


def _instante(texto: Any) -> dt.datetime | None:
    if not isinstance(texto, str):
        return None
    try:
        t = dt.datetime.fromisoformat(texto.strip().replace("Z", "+00:00").replace(" ", "T"))
    except ValueError:
        return None
    return t if t.tzinfo else t.replace(tzinfo=dt.timezone.utc)


def resumir(
    geojson: bytes, lat: float, lon: float, raio_km: int, agora: dt.datetime,
) -> dict[str, Any]:
    """Conta detecções no raio (24 h e 48 h). Registros sem coordenada ou sem horário são ignorados."""
    agora = agora.astimezone(dt.timezone.utc)
    t24, t48 = agora - dt.timedelta(hours=24), agora - dt.timedelta(hours=48)
    n24 = n48 = 0
    mais_perto: float | None = None
    ultima: dt.datetime | None = None
    frp_max: float | None = None
    for f in json.loads(geojson).get("features", []):
        p = f.get("properties") or {}
        la, lo = p.get("latitude"), p.get("longitude")
        coords = (f.get("geometry") or {}).get("coordinates")
        if (la is None or lo is None) and coords:
            lo, la = coords[0], coords[1]
        t = _instante(p.get("data_hora_gmt"))
        if not isinstance(la, (int, float)) or not isinstance(lo, (int, float)) or t is None:
            continue
        d = distancia_km(lat, lon, float(la), float(lo))
        if d > raio_km or t < t48 or t > agora + dt.timedelta(minutes=5):
            continue
        n48 += 1
        if t >= t24:
            n24 += 1
        mais_perto = d if mais_perto is None else min(mais_perto, d)
        ultima = t if ultima is None else max(ultima, t)
        frp = p.get("frp")
        if isinstance(frp, (int, float)):
            frp_max = float(frp) if frp_max is None else max(frp_max, float(frp))
    return {
        "raio_km": raio_km,
        "focos_24h": n24,
        "focos_48h": n48,
        "mais_proximo_km": None if mais_perto is None else round(mais_perto, 1),
        "ultima_deteccao_utc": None if ultima is None else ultima.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "frp_max_mw": None if frp_max is None else round(frp_max, 1),
    }
