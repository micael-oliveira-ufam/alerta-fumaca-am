"""Bairros de Manaus: cache de geocodificação, ranking e mínimos de privacidade."""

import threading

from app import bairros
from app.config import Settings
from app.db import make_session_factory

from .conftest import payload


def _enviar(client, n, **over):
    for _ in range(n):
        assert client.post("/respostas", json=payload(**over)).status_code == 201


def _falso(tabela):
    chamadas = []

    def geocodificar(lat, lon):
        chamadas.append((lat, lon))
        return tabela.get((round(lat, 2), round(lon, 2)))

    geocodificar.chamadas = chamadas
    return geocodificar


def test_ranking_soma_por_bairro_e_respeita_o_minimo(engine, make_client):
    c = make_client()
    _enviar(c, 4, lat=-3.10, lon=-60.02, nivel="high")
    _enviar(c, 2, lat=-3.11, lon=-60.02)  # outro bairro, abaixo do mínimo (3)
    _enviar(c, 3, lat=-3.12, lon=-60.03)  # mesmo bairro do primeiro
    fabrica = make_session_factory(engine)
    geo = _falso({
        (-3.10, -60.02): {"bairro": "Centro", "cidade": "Manaus"},
        (-3.12, -60.03): {"bairro": "Centro", "cidade": "Manaus"},
        (-3.11, -60.02): {"bairro": "Adrianópolis", "cidade": "Manaus"},
    })
    assert bairros.resolver_pendentes(fabrica, geo, pausa=0) == 3
    with fabrica() as s:
        r = bairros.ranking(s, Settings(database_url="sqlite://", min_respostas_celula=3), 30)
    assert r["bairros"] == [{"bairro": "Centro", "respostas": 7, "alto_ou_emergencia": 4}]
    assert r["areas_em_consulta"] == 0


def test_cada_celula_e_consultada_uma_vez(engine, make_client):
    c = make_client()
    _enviar(c, 3, lat=-3.10, lon=-60.02)
    fabrica = make_session_factory(engine)
    geo = _falso({(-3.10, -60.02): {"bairro": "Centro", "cidade": "Manaus"}})
    bairros.resolver_pendentes(fabrica, geo, pausa=0)
    bairros.resolver_pendentes(fabrica, geo, pausa=0)
    assert len(geo.chamadas) == 1


def test_falha_do_geocodificador_nao_grava_e_tenta_depois(engine, make_client):
    c = make_client()
    _enviar(c, 3, lat=-3.10, lon=-60.02)
    fabrica = make_session_factory(engine)
    assert bairros.resolver_pendentes(fabrica, lambda la, lo: None, pausa=0) == 0
    geo = _falso({(-3.10, -60.02): {"bairro": "Centro", "cidade": "Manaus"}})
    assert bairros.resolver_pendentes(fabrica, geo, pausa=0) == 1


def test_fora_de_manaus_nao_e_geocodificado_nem_listado(engine, make_client):
    c = make_client()
    _enviar(c, 5, lat=-9.97, lon=-67.81)  # Rio Branco
    fabrica = make_session_factory(engine)
    geo = _falso({})
    assert bairros.resolver_pendentes(fabrica, geo, pausa=0) == 0
    assert geo.chamadas == []


def test_resultado_de_outra_cidade_nao_entra_no_ranking(engine, make_client):
    c = make_client()
    _enviar(c, 5, lat=-3.10, lon=-60.02)
    fabrica = make_session_factory(engine)
    geo = _falso({(-3.10, -60.02): {"bairro": "Centro", "cidade": "Iranduba"}})
    bairros.resolver_pendentes(fabrica, geo, pausa=0)
    with fabrica() as s:
        assert bairros.ranking(s, Settings(database_url="sqlite://", min_respostas_celula=3), 30)["bairros"] == []


def test_endpoint_publico_sem_senha_e_sem_vazar_celula(make_client):
    c = make_client(admin_token="segredo")
    _enviar(c, 3, lat=-3.10, lon=-60.02)
    r = c.get("/bairros?dias=30")
    assert r.status_code == 200
    corpo = r.json()
    assert corpo["areas_em_consulta"] == 1 and corpo["bairros"] == []
    assert "lat" not in r.text and "submission" not in r.text


def test_painel_publico_inclui_bairros(make_client):
    c = make_client()
    _enviar(c, 6)
    d = c.get("/publico/painel?dias=30").json()
    assert "bairros" in d and d["bairros"]["minimo_por_bairro"] == 3


def test_disparo_em_segundo_plano_resolve_as_celulas(engine):
    from fastapi.testclient import TestClient
    from app.main import create_app
    from .conftest import TEST_DB

    geo = _falso({(-3.10, -60.02): {"bairro": "Centro", "cidade": "Manaus"}})
    settings = Settings(database_url=TEST_DB, rate_limit_per_min=0, geocoder_ativo=True)
    with TestClient(create_app(settings, engine, geocoder=geo)) as c:
        _enviar(c, 3, lat=-3.10, lon=-60.02)
        assert c.get("/bairros").json()["areas_em_consulta"] == 1
        c.app.state.bairros_thread.join(timeout=5)
        r = c.get("/bairros").json()
    assert r["bairros"] == [{"bairro": "Centro", "respostas": 3, "alto_ou_emergencia": 0}]
    assert isinstance(c.app.state.bairros_thread, threading.Thread)
