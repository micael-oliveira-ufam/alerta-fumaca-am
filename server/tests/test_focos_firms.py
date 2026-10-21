"""Segunda fonte de focos (NASA FIRMS): conversão, reserva do INPE, escolha na página e sigilo da chave.
Todos os dados são sintéticos; nenhum teste acessa a rede."""
import csv
import datetime as dt
import io
import json
import logging

import pytest
import requests

from app import focos, focos_firms

CHAVE = "CHAVE-DE-TESTE-NAO-VAZAR"
AGORA = dt.datetime(2026, 10, 20, 18, 0, tzinfo=dt.timezone.utc)


def _csv(fonte, linhas):
    cab = "latitude,longitude,bright_ti4,scan,track,acq_date,acq_time,satellite,instrument,confidence,version,bright_ti5,frp,daynight"
    if fonte == "MODIS_NRT":
        cab = cab.replace("bright_ti4", "brightness").replace("bright_ti5", "bright_t31")
    return cab + "\n" + "\n".join(linhas) + "\n"


def _linha(lat, lon, data, hhmm, sat="N", frp="3.5"):
    return f"{lat},{lon},330,0.4,0.4,{data},{hhmm},{sat},VIIRS,n,2.0NRT,290,{frp},D"


def test_converter_mapeia_para_o_formato_do_inpe():
    f = focos_firms.converter(_csv("VIIRS_SNPP_NRT", [_linha(-3.1, -60.0, "2026-10-20", "516")]), "VIIRS_SNPP_NRT", AGORA)
    assert len(f) == 1
    p = f[0]["properties"]
    assert p["data_hora_gmt"] == "2026-10-20 05:16:00" and p["satelite"] == "NPP-375"
    assert p["municipio"] is None and p["fonte"] == "NASA FIRMS" and p["frp"] == 3.5


def test_converter_ignora_fora_da_janela_e_linhas_ruins():
    linhas = [_linha(-3, -60, "2026-10-10", "100"), _linha("x", -60, "2026-10-20", "100"), _linha(-3, -60, "2026-10-21", "100")]
    assert focos_firms.converter(_csv("VIIRS_SNPP_NRT", linhas), "VIIRS_SNPP_NRT", AGORA) == []


def test_converter_rejeita_resposta_que_nao_e_csv():
    with pytest.raises(focos_firms.FirmsErro):
        focos_firms.converter("Invalid MAP_KEY", "MODIS_NRT", AGORA)


def _http(falhar=()):
    def get(url, **k):
        for fonte in focos_firms.FONTES:
            if fonte in url:
                if fonte in falhar:
                    raise requests.exceptions.ConnectionError(f"boom {url}")
                r = requests.Response(); r.status_code = 200
                sat = "Terra" if fonte == "MODIS_NRT" else "N"
                r._content = _csv(fonte, [_linha(-3, -60, "2026-10-20", "1200", sat)]).encode()
                return r
        raise AssertionError(url)
    return get


def test_fetch_geojson_tolera_falha_parcial_e_so_falha_se_todas_falham():
    corpo = focos_firms.fetch_geojson(CHAVE, agora=AGORA, http_get=_http(falhar=("MODIS_NRT",)))
    assert len(json.loads(corpo)["features"]) == 3
    with pytest.raises(focos_firms.FirmsErro) as e:
        focos_firms.fetch_geojson(CHAVE, agora=AGORA, http_get=_http(falhar=focos_firms.FONTES))
    assert CHAVE not in str(e.value) and "http" not in str(e.value)


def test_chave_recusada_e_ausente():
    def get(url, **k):
        r = requests.Response(); r.status_code = 403; r._content = b""; return r
    with pytest.raises(focos_firms.FirmsErro) as e:
        focos_firms.fetch_geojson(CHAVE, agora=AGORA, http_get=get)
    assert "recusada" in e.value.motivo_publico and CHAVE not in e.value.motivo_publico
    with pytest.raises(focos_firms.FirmsErro):
        focos_firms.fetch_geojson("", agora=AGORA)


@pytest.fixture()
def app_com_chave(make_client):
    return make_client(firms_map_key=CHAVE)


def _geo(n, fonte=None):
    p = {"data_hora_gmt": "2026-10-20 12:00:00", "satelite": "NOAA-20", "latitude": -3.0, "longitude": -60.0, "frp": 2}
    if fonte:
        p["fonte"] = fonte
    return json.dumps({"type": "FeatureCollection", "features": [{"type": "Feature", "geometry": None, "properties": p}] * n}).encode()


def _inpe_cai(monkeypatch):
    def falha(*a, **k):
        raise requests.exceptions.ReadTimeout(f"https://x?k={CHAVE}")
    monkeypatch.setattr(focos, "fetch_upstream", falha)


def test_inpe_cai_e_firms_assume(app_com_chave, monkeypatch):
    _inpe_cai(monkeypatch)
    monkeypatch.setattr(focos_firms, "fetch_geojson", lambda *a, **k: _geo(2, "NASA FIRMS"))
    r = app_com_chave.get("/focos?window=last48h&scope=amazonas")
    assert r.status_code == 200 and r.headers["x-fonte"] == "FIRMS" and r.headers["x-fonte-solicitada"] == "INPE"
    assert len(r.json()["features"]) == 2


def test_inpe_ok_nao_consulta_firms(app_com_chave, monkeypatch):
    monkeypatch.setattr(focos, "fetch_upstream", lambda *a, **k: _geo(1))
    monkeypatch.setattr(focos_firms, "fetch_geojson", lambda *a, **k: pytest.fail("não deveria chamar"))
    r = app_com_chave.get("/focos?window=last48h&scope=amazonas")
    assert r.headers["x-fonte"] == "INPE"


def test_fonte_firms_escolhida_tem_cache_proprio(app_com_chave, monkeypatch):
    monkeypatch.setattr(focos, "fetch_upstream", lambda *a, **k: _geo(1))
    monkeypatch.setattr(focos_firms, "fetch_geojson", lambda *a, **k: _geo(5, "NASA FIRMS"))
    a = app_com_chave.get("/focos?window=last48h&scope=amazonas&fonte=firms")
    b = app_com_chave.get("/focos?window=last48h&scope=amazonas")
    assert a.headers["x-fonte"] == "FIRMS" and a.headers["x-fonte-solicitada"] == "FIRMS" and len(a.json()["features"]) == 5
    assert b.headers["x-fonte"] == "INPE" and len(b.json()["features"]) == 1


def test_firms_so_cobre_o_amazonas(app_com_chave):
    assert app_com_chave.get("/focos?window=last48h&scope=brasil&fonte=firms").status_code == 422


def test_firms_sem_chave_da_404_e_fontes_informa(client):
    assert client.get("/focos?window=last48h&scope=amazonas&fonte=firms").status_code == 404
    assert client.get("/focos/fontes").json() == {"inpe": True, "firms": False}


def test_fontes_com_chave(app_com_chave):
    j = app_com_chave.get("/focos/fontes")
    assert j.json() == {"inpe": True, "firms": True} and CHAVE not in j.text


def test_tudo_cai_502_combina_motivos_sem_vazar_chave(app_com_chave, monkeypatch, caplog):
    _inpe_cai(monkeypatch)
    def firms_falha(*a, **k):
        raise focos_firms.FirmsErro("chave do FIRMS recusada")
    monkeypatch.setattr(focos_firms, "fetch_geojson", firms_falha)
    with caplog.at_level(logging.DEBUG):
        r = app_com_chave.get("/focos?window=last48h&scope=amazonas")
    d = r.json()["detail"]
    assert r.status_code == 502 and "INPE:" in d and "NASA FIRMS: chave do FIRMS recusada" in d
    assert CHAVE not in r.text and CHAVE not in caplog.text.replace(f"k={CHAVE}", "")


def test_stale_vem_da_origem_guardada(app_com_chave, monkeypatch):
    monkeypatch.setattr(focos, "fetch_upstream", lambda *a, **k: _geo(1))
    app_com_chave.get("/focos?window=last48h&scope=amazonas")
    app_com_chave.app.state.focos_cache.ttl_s = -1
    _inpe_cai(monkeypatch)
    monkeypatch.setattr(focos_firms, "fetch_geojson", lambda *a, **k: (_ for _ in ()).throw(focos_firms.FirmsErro("x")))
    r = app_com_chave.get("/focos?window=last48h&scope=amazonas")
    assert r.headers["x-cache"] == "STALE" and r.headers["x-fonte"] == "INPE"


def test_csv_de_focos_tem_coluna_fonte(app_com_chave, monkeypatch):
    _inpe_cai(monkeypatch)
    monkeypatch.setattr(focos_firms, "fetch_geojson", lambda *a, **k: _geo(1, "NASA FIRMS"))
    r = app_com_chave.get("/publico/export.csv?conjunto=focos")
    linhas = list(csv.reader(io.StringIO(r.content.decode("utf-8-sig"))))
    assert linhas[0][-1] == "fonte" and linhas[1][-1] == "NASA FIRMS"


def test_app_focos_indica_firms(app_com_chave, monkeypatch):
    _inpe_cai(monkeypatch)
    monkeypatch.setattr(focos_firms, "fetch_geojson", lambda *a, **k: _geo(1, "NASA FIRMS"))
    j = app_com_chave.get("/app/focos?cod=1302603&raio_km=50").json()
    assert j["fonte_id"] == "FIRMS" and "NASA" in j["fonte"] and "caixa" in j["nota"]
