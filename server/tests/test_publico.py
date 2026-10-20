"""Painel público: sem senha, só dados agregados e com as regras de privacidade."""

import json

import pytest

from .conftest import payload


def _enviar(client, n, **over):
    for _ in range(n):
        r = client.post("/respostas", json=payload(**over))
        assert r.status_code == 201, r.text


def test_pagina_e_dados_abrem_sem_senha_mesmo_com_admin_token(make_client):
    client = make_client(admin_token="segredo-do-admin")
    pagina = client.get("/")
    assert pagina.status_code == 200
    assert "Painel público" in pagina.text or "painel público" in pagina.text
    assert "default-src 'self'" in pagina.headers["content-security-policy"]
    dados = client.get("/publico/painel?dias=30")
    assert dados.status_code == 200
    assert client.get("/assets/publico.js").status_code == 200
    assert client.get("/assets/publico.css").status_code == 200
    assert client.get("/vendor/leaflet/leaflet.js").status_code == 200


def test_abaixo_do_minimo_devolve_so_o_total(client):
    _enviar(client, 3)
    d = client.get("/publico/painel?dias=30").json()
    assert d["suficiente"] is False
    assert d["total_respostas"] == 3
    assert d["faltam"] == 2
    for chave in ("sintomas", "niveis", "mapa", "perfil", "contexto", "serie_diaria"):
        assert chave not in d


def test_com_respostas_suficientes_mostra_sintomas_e_niveis(client):
    _enviar(client, 6, sintomas={"cough": 2, "headache": 1, "dyspnea": 0})
    d = client.get("/publico/painel?dias=7").json()
    assert d["suficiente"] is True
    ids = {s["id"]: s for s in d["sintomas"]}
    assert ids["cough"]["relatos"] == 6
    assert ids["cough"]["rotulo"] == "Tosse"
    assert ids["dyspnea"]["relatos"] == 0
    assert d["niveis"]["moderate"] == 6
    assert d["serie_diaria"][0]["respostas"] == 6


def test_nada_individual_vaza(client):
    _enviar(client, 6)
    bruto = client.get("/publico/painel?dias=30").text
    dados = json.loads(bruto)
    assert "submission_id" not in bruto
    assert "registrado_em" not in bruto
    assert "criado_em" not in bruto
    assert "recentes" not in dados
    # A API pública não aceita enumerar respostas por id.
    assert client.get("/respostas/1").status_code in (404, 405)
    # Coordenada só no formato de célula (2 casas).
    for c in dados["mapa"]["celulas"]:
        assert round(c["lat"], 2) == c["lat"] and round(c["lon"], 2) == c["lon"]


def test_contagens_pequenas_de_perfil_sao_escondidas(make_client):
    sem = {"idoso": False, "gestante": False}
    c1 = make_client()
    _enviar(c1, 5, perfil=sem)
    _enviar(c1, 2, perfil={"idoso": False, "gestante": True})
    d = c1.get("/publico/painel?dias=30").json()
    assert d["perfil"]["gestante"] is None  # 2 < mínimo por área (3)
    assert d["perfil"]["idoso"] == 0  # zero não é escondido

    _enviar(c1, 1, perfil={"idoso": False, "gestante": True})  # agora são 3
    c1.app.state.publico_cache.clear()  # ignora o cache de 10 s
    assert c1.get("/publico/painel?dias=30").json()["perfil"]["gestante"] == 3


def test_area_do_mapa_so_com_minimo_de_respostas(client):
    _enviar(client, 5, lat=-3.119, lon=-60.0217)
    _enviar(client, 2, lat=-10.5, lon=-65.5)
    celulas = client.get("/publico/painel?dias=30").json()["mapa"]["celulas"]
    assert len(celulas) == 1 and celulas[0]["respostas"] == 5


def test_contexto_com_poucas_respostas_e_omitido(client):
    _enviar(client, 6)  # sem contexto
    _enviar(client, 2, contexto={"mascara": "pff2_n95"})
    d = client.get("/publico/painel?dias=30").json()
    assert "mascara" not in d["contexto"]


def test_periodo_invalido_e_rejeitado(client):
    assert client.get("/publico/painel?dias=13").status_code == 422


def test_resultado_e_reaproveitado_por_alguns_segundos(client):
    _enviar(client, 5)
    primeiro = client.get("/publico/painel?dias=30").json()
    _enviar(client, 1)
    segundo = client.get("/publico/painel?dias=30").json()
    assert segundo["total_respostas"] == primeiro["total_respostas"] == 5  # cache de 10 s
    assert "max-age" in client.get("/publico/painel?dias=30").headers["cache-control"]


def test_exportacao_csv_continua_exigindo_token(make_client):
    client = make_client(admin_token="segredo-do-admin")
    assert client.get("/respostas/export.csv").status_code in (401, 403)


def test_referrer_policy_permite_tiles_do_osm(client):
    """O OpenStreetMap bloqueia (403) tiles pedidos sem Referer; a página precisa enviar ao menos a origem."""
    r = client.get("/")
    assert r.headers["Referrer-Policy"] == "strict-origin-when-cross-origin"
