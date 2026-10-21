"""Via dos CSV diários do INPE (dados abertos): conversão, filtros, janela e a ordem das fontes."""

import datetime as dt
import json

import pytest

from app import focos, focos_inpe_csv
from app.focos_inpe_csv import CsvInpeErro, converter, fetch_geojson

AGORA = dt.datetime(2026, 10, 20, 12, 0, tzinfo=dt.timezone.utc)
CAB = "id,lat,lon,data_hora_gmt,satelite,municipio,estado,pais,municipio_id,estado_id,pais_id,numero_dias_sem_chuva,precipitacao,risco_fogo,bioma,frp"


def _linha(lat, lon, quando, sat="NOAA-20", mun="Lábrea", uf="AMAZONAS", frp="12.5", dias="9", risco="0.8"):
    return f"x,{lat},{lon},{quando},{sat},{mun},{uf},Brasil,1,13,33,{dias},0.0,{risco},Amazônia,{frp}"


def test_converte_filtra_estado_satelite_e_janela():
    linhas = [CAB,
              _linha(-7.2, -64.8, "2026-10-20 10:00:00"),
              _linha(-7.3, -64.9, "2026-10-20 10:05:00", uf="Pará"),                  # outro estado
              _linha(-7.4, -65.0, "2026-10-20 10:10:00", sat="GOES-19"),             # satélite não pedido
              _linha(-7.5, -65.1, "2026-10-17 10:00:00"),                            # fora das 48 h
              _linha(-7.6, -65.2, "2026-10-20 23:00:00"),                            # no futuro
              _linha("abc", -65.2, "2026-10-20 10:00:00"),                           # lixo
              "linha curta"]
    f = converter(linhas, AGORA, satelites=["NOAA-20"])
    assert len(f) == 1
    p = f[0]["properties"]
    assert f[0]["geometry"] is None and p["latitude"] == -7.2 and p["longitude"] == -64.8
    assert p["estado"] == "AMAZONAS" and p["municipio"] == "LÁBREA" and p["satelite"] == "NOAA-20"
    assert p["data_hora_gmt"] == "2026-10-20T10:00:00Z" and p["frp"] == 12.5 and p["numero_dias_sem_chuva"] == 9


def test_estado_sem_acento_ou_caixa_e_ponto_e_virgula_com_virgula_decimal():
    cab = CAB.replace(",", ";")
    linha = "x;-7,2;-64,8;2026-10-20 10:00:00;NOAA-20;Lábrea;Amazonas;Brasil;1;13;33;9;0,0;0,8;Amazônia;12,5"
    f = converter([cab, linha], AGORA)
    assert len(f) == 1 and f[0]["properties"]["latitude"] == -7.2 and f[0]["properties"]["frp"] == 12.5
    assert f[0]["properties"]["estado"] == "AMAZONAS"


def test_brasil_nao_filtra_estado_e_cabecalho_errado_falha():
    f = converter([CAB, _linha(-7.3, -64.9, "2026-10-20 10:05:00", uf="Pará")], AGORA, amazonas=False)
    assert len(f) == 1
    with pytest.raises(CsvInpeErro):
        converter(["a,b,c", "1,2,3"], AGORA)
    with pytest.raises(CsvInpeErro):
        converter([], AGORA)


class _Resp:
    def __init__(self, status, linhas=()):
        self.status_code, self._l = status, list(linhas)

    def iter_lines(self, decode_unicode=False):
        return iter([l.encode() for l in self._l])

    def close(self):
        pass


def test_fetch_usa_os_dias_que_existem_e_ignora_404():
    pedidos = []

    def http_get(url, **k):
        pedidos.append(url)
        if url.endswith("20261020.csv"):
            return _Resp(200, [CAB, _linha(-7.2, -64.8, "2026-10-20 10:00:00")])
        if url.endswith("20261019.csv"):
            return _Resp(200, [CAB, _linha(-7.3, -64.9, "2026-10-19 15:00:00")])
        return _Resp(404)

    d = json.loads(fetch_geojson("amazonas", agora=AGORA, http_get=http_get))
    assert d["type"] == "FeatureCollection" and len(d["features"]) == 2
    assert [u.rsplit("_", 1)[1] for u in pedidos] == ["20261020.csv", "20261019.csv", "20261018.csv"]
    assert d["features"][0]["properties"]["data_hora_gmt"] < d["features"][1]["properties"]["data_hora_gmt"]


def test_fetch_falha_se_nenhum_arquivo_for_lido():
    with pytest.raises(CsvInpeErro):
        fetch_geojson("amazonas", agora=AGORA, http_get=lambda *a, **k: _Resp(404))
    with pytest.raises(CsvInpeErro) as e:
        fetch_geojson("amazonas", agora=AGORA, http_get=lambda *a, **k: _Resp(503))
    assert "503" in e.value.motivo_publico


def test_servidor_cai_do_wfs_para_o_csv_do_inpe_e_pausa_o_wfs(client, monkeypatch):
    chamadas = {"wfs": 0}

    def wfs_404(*a, **k):
        chamadas["wfs"] += 1
        raise ValueError("status 404")

    monkeypatch.setattr(focos, "fetch_upstream", wfs_404)
    corpo = json.dumps({"type": "FeatureCollection", "features": [{"type": "Feature", "geometry": None,
        "properties": {"data_hora_gmt": "2026-10-20T10:00:00Z", "satelite": "NOAA-20", "estado": "AMAZONAS",
                       "latitude": -7.2, "longitude": -64.8}}]}).encode()
    monkeypatch.setattr(focos_inpe_csv, "fetch_geojson", lambda *a, **k: corpo)
    r = client.get("/focos?window=last48h&scope=amazonas")
    assert r.status_code == 200 and r.headers["x-fonte"] == "INPE" and r.content == corpo
    # outra combinação (sem cache): o WFS que falhou fica em pausa e não é consultado de novo
    r2 = client.get("/focos?window=today&scope=amazonas")
    assert r2.status_code == 200 and chamadas["wfs"] == 1
