"""Testes do proxy dos focos, com o INPE simulado (sem acesso à rede)."""

import threading
import time

import pytest
import requests

from app import focos

SAMPLE = (
    b'{"type":"FeatureCollection","features":['
    b'{"type":"Feature","geometry":null,"properties":{"longitude":-60.0217,"latitude":-3.119,'
    b'"estado":"AMAZONAS","satelite":"NOAA-20","data_hora_gmt":"2026-10-19T10:00:00Z","frp":12.5}}]}'
)


# ----------------------------------------------------------------- parâmetros WFS


def test_parametros_amazonas_com_satelites():
    p = focos.build_params("today", "amazonas", ["NPP-375", "AQUA_M-T"])
    assert p["typeName"] == "dados_abertos:focos_48h_br_todosats"
    assert p["CQL_FILTER"] == "estado='AMAZONAS' AND satelite IN ('AQUA_M-T','NPP-375')"
    assert p["propertyName"].startswith("longitude,latitude")  # geometria vem como propriedade


def test_parametros_brasil_nao_filtram_estado():
    p = focos.build_params("last48h", "brasil", ["NOAA-20"])
    assert p["typeName"] == "dados_abertos:focos_48h_br_todosats"
    assert p["CQL_FILTER"] == "satelite IN ('NOAA-20')"


def test_satelite_fora_da_lista_nunca_entra_na_consulta():
    with pytest.raises(ValueError):
        focos.build_params("today", "brasil", ["NOAA-20') OR 1=1 --"])


def test_validacao_do_geojson():
    assert focos.is_feature_collection(SAMPLE)
    assert not focos.is_feature_collection(b"<ServiceExceptionReport/>")
    assert not focos.is_feature_collection(b'{"type":"ServiceException"}')


# ------------------------------------------------------------------------ endpoint


def test_miss_depois_hit_e_filtros_repassados(client, monkeypatch):
    chamadas = []

    def falso(window, scope, sats):
        chamadas.append((window, scope, tuple(sorted(sats))))
        return SAMPLE

    monkeypatch.setattr(focos, "fetch_upstream", falso)
    q = "/focos?window=today&scope=brasil&satellites=NOAA-20,NPP-375"
    a, b = client.get(q), client.get(q)

    assert a.status_code == 200 and a.headers["X-Cache"] == "MISS"
    assert b.headers["X-Cache"] == "HIT"
    assert len(chamadas) == 1  # o segundo pedido não foi ao INPE
    assert chamadas[0] == ("today", "brasil", ("NOAA-20", "NPP-375"))
    assert a.content == SAMPLE


def test_respostas_grandes_saem_comprimidas(client, monkeypatch):
    grande = SAMPLE[:-2] + b',{"type":"Feature","geometry":null,"properties":{"x":"' + b"a" * 5000 + b'"}}]}'
    monkeypatch.setattr(focos, "fetch_upstream", lambda *a: grande)
    r = client.get("/focos?window=today", headers={"accept-encoding": "gzip"})
    assert r.status_code == 200
    assert r.headers.get("content-encoding") == "gzip"
    assert r.content == grande  # o cliente HTTP descomprime; o conteúdo é idêntico


def test_combinacoes_diferentes_nao_compartilham_cache(client, monkeypatch):
    n = []
    monkeypatch.setattr(focos, "fetch_upstream", lambda *a: n.append(a) or SAMPLE)
    client.get("/focos?window=today&scope=amazonas")
    client.get("/focos?window=today&scope=brasil")
    client.get("/focos?window=last48h&scope=amazonas")
    assert len(n) == 3


def test_entrega_cache_vencido_quando_o_inpe_falha(make_client, monkeypatch):
    c = make_client(cache_seconds=0)  # expira imediatamente
    monkeypatch.setattr(focos, "fetch_upstream", lambda *a: SAMPLE)
    c.get("/focos?window=last48h")

    def falha(*a):
        raise requests.ConnectionError("DNS")

    monkeypatch.setattr(focos, "fetch_upstream", falha)
    r = c.get("/focos?window=last48h")
    assert r.status_code == 200 and r.headers["X-Cache"] == "STALE"
    assert r.content == SAMPLE


def test_502_quando_falha_e_nao_ha_cache(client, monkeypatch):
    def falha(*a):
        raise requests.ConnectionError("DNS")

    monkeypatch.setattr(focos, "fetch_upstream", falha)
    assert client.get("/focos?window=today").status_code == 502


def test_resposta_fora_do_formato_vira_502(client, monkeypatch):
    def invalida(*a):
        raise ValueError("resposta fora do formato GeoJSON")

    monkeypatch.setattr(focos, "fetch_upstream", invalida)
    assert client.get("/focos?window=today").status_code == 502


def test_parametros_invalidos(client):
    assert client.get("/focos?window=ontem").status_code == 422
    assert client.get("/focos?window=today&scope=mundo").status_code == 422
    r = client.get("/focos?window=today&satellites=NOAA-20,SATELITE_FALSO")
    assert r.status_code == 422 and "SATELITE_FALSO" in r.text


def test_pedidos_simultaneos_fazem_uma_unica_consulta(client, monkeypatch):
    chamadas = []

    def lento(*a):
        chamadas.append(1)
        time.sleep(0.3)
        return SAMPLE

    monkeypatch.setattr(focos, "fetch_upstream", lento)
    resultados = []

    def pedir():
        resultados.append(client.get("/focos?window=today").status_code)

    threads = [threading.Thread(target=pedir) for _ in range(5)]
    [t.start() for t in threads]
    [t.join() for t in threads]

    assert resultados == [200] * 5
    assert len(chamadas) == 1


# ------------------------------------------------------------------ cache (unidade)


def test_cache_descarta_a_entrada_mais_antiga_ao_passar_do_limite():
    cache = focos.FocosCache(ttl_s=300, max_entries=2)
    cache.store("a", b"1")
    cache.store("b", b"2")
    cache.fresh("a")  # "a" passa a ser a mais recente
    cache.store("c", b"3")  # estoura o limite: sai "b"
    assert cache.last_valid("a") == b"1"
    assert cache.last_valid("b") is None
    assert cache.last_valid("c") == b"3"
    assert len(cache) == 2


def test_cache_expira_pelo_ttl():
    agora = [0.0]
    cache = focos.FocosCache(ttl_s=10, clock=lambda: agora[0])
    cache.store("k", b"x")
    agora[0] = 9.9
    assert cache.fresh("k") == b"x"
    agora[0] = 10.1
    assert cache.fresh("k") is None
    assert cache.last_valid("k") == b"x"  # continua disponível como "vencido"
