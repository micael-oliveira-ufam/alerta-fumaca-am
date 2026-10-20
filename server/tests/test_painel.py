"""Painel do administrador (app.painel) e identificação da origem atrás do túnel."""

import datetime as dt

import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app
from app.painel import create_painel_app, descobrir_link

from .conftest import TEST_DB, payload


def _settings(**over) -> Settings:
    params = dict(
        database_url=TEST_DB, rate_limit_per_min=0, min_respostas_publicas=5,
        min_respostas_celula=3, admin_token="",
    )
    params.update(over)
    return Settings(**params)


@pytest.fixture()
def make_painel(engine):
    abertos = []

    def _make(**over) -> TestClient:
        c = TestClient(create_painel_app(_settings(**over), engine))
        c.__enter__()
        abertos.append(c)
        return c

    yield _make
    for c in abertos:
        c.__exit__(None, None, None)


def _enviar(client, **over):
    r = client.post("/respostas", json=payload(**over))
    assert r.status_code == 201, r.text


# ------------------------------------------------------------------ página e acesso


def test_pagina_e_cabecalhos_de_seguranca(make_painel):
    r = make_painel().get("/")
    assert r.status_code == 200 and "Painel" in r.text
    assert "script-src 'self'" in r.headers["content-security-policy"]
    assert r.headers["cache-control"] == "no-store"
    assert r.headers["x-content-type-options"] == "nosniff"


def test_arquivos_estaticos_incluem_o_leaflet_local(make_painel):
    c = make_painel()
    assert c.get("/static/painel.js").status_code == 200
    assert c.get("/static/vendor/leaflet/leaflet.js").status_code == 200


def test_sem_token_configurado_o_painel_abre(make_painel):
    assert make_painel().get("/api/painel").status_code == 200


def test_com_token_exige_o_cabecalho(make_painel):
    c = make_painel(admin_token="segredo")
    assert c.get("/api/painel").status_code == 401
    assert c.get("/api/painel", headers={"X-Admin-Token": "errado"}).status_code == 401
    assert c.get("/api/painel", headers={"X-Admin-Token": "segredo"}).status_code == 200
    assert c.get("/api/qr.svg").status_code == 401


def test_tentativas_de_token_invalido_sao_limitadas(make_painel):
    c = make_painel(admin_token="segredo")
    codigos = [c.get("/api/painel", headers={"X-Admin-Token": "x"}).status_code for _ in range(12)]
    assert codigos[:10] == [401] * 10 and codigos[10:] == [429, 429]
    # mesmo bloqueado, o token certo continua entrando
    assert c.get("/api/painel", headers={"X-Admin-Token": "segredo"}).status_code == 200


# ------------------------------------------------------------------------- números


def test_painel_vazio(make_painel):
    d = make_painel().get("/api/painel").json()
    assert d["servidor"]["banco"] == "ok"
    assert d["resumo"]["total"] == 0 and d["resumo"]["ultima_resposta"] is None
    assert d["recentes"] == [] and d["mapa"] == []
    assert len(d["serie_horaria"]) == 48 and sum(h["respostas"] for h in d["serie_horaria"]) == 0


def test_numeros_batem_com_o_que_foi_enviado(client, make_painel):
    _enviar(client, nivel="low", sintomas={"cough": 1, "headache": 0}, perfil={"idoso": True})
    _enviar(client, nivel="high", sintomas={"cough": 3, "headache": 2}, perfil={"gestante": True})
    _enviar(client, nivel="high", sintomas={"cough": 2}, perfil={})
    d = make_painel().get("/api/painel?limite=2").json()
    r = d["resumo"]
    assert (r["total"], r["ultimas_24h"], r["ultima_hora"], r["total_30d"]) == (3, 3, 3, 3)
    assert r["niveis_24h"] == {"low": 1, "moderate": 0, "high": 2, "emergency": 0}
    cough = next(s for s in r["sintomas_30d"] if s["id"] == "cough")
    assert (cough["relatos"], cough["leve"], cough["moderado"], cough["intenso"]) == (3, 1, 1, 1)
    assert cough["percentual"] == 100.0 and cough["gravidade_media"] == 2.0
    assert cough["rotulo"] == "Tosse"
    head = next(s for s in r["sintomas_30d"] if s["id"] == "headache")
    assert head["relatos"] == 1 and head["percentual"] == 33.3
    assert r["perfil_30d"]["idoso"] == 1 and r["perfil_30d"]["gestante"] == 1
    # ordem: mais relatado primeiro
    assert [s["id"] for s in r["sintomas_30d"]][:2] == ["cough", "headache"]
    # série por hora soma o total e tudo cai na hora atual
    assert sum(h["respostas"] for h in d["serie_horaria"]) == 3
    assert d["serie_horaria"][-1]["respostas"] == 3
    # recentes: do mais novo para o mais antigo, respeitando o limite
    assert len(d["recentes"]) == 2 and d["recentes"][0]["id"] > d["recentes"][1]["id"]


def test_recentes_mostra_so_sintomas_relatados_e_local_arredondado(client, make_painel):
    _enviar(client, lat=-3.119042, lon=-60.021749, sintomas={"cough": 2, "dyspnea": 0, "eyes": 3})
    item = make_painel().get("/api/painel").json()["recentes"][0]
    assert [s["id"] for s in item["sintomas"]] == ["eyes", "cough"]  # gravidade desc., sem o 0
    assert (item["lat"], item["lon"]) == (-3.12, -60.02)
    assert not {"submission_id", "ip", "nome"} & set(item)


def test_mapa_do_painel_inclui_areas_com_poucas_respostas(client, make_painel):
    _enviar(client)  # 1 resposta: a API pública oculta (mínimo 3)
    assert client.get("/mapa").json()["celulas"] == []
    cel = make_painel().get("/api/painel").json()["mapa"]
    assert len(cel) == 1 and cel[0]["respostas"] == 1 and cel[0]["pior_nivel"] == "moderate"


def test_resposta_antiga_fica_fora_de_24h_mas_entra_no_total(client, make_painel, engine):
    from sqlalchemy import text
    from sqlalchemy.orm import Session

    _enviar(client)
    antigo = (dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=3)).isoformat()
    with Session(engine) as s:
        s.execute(text("UPDATE respostas SET criado_em = :t"), {"t": antigo})
        s.commit()
    r = make_painel().get("/api/painel").json()["resumo"]
    assert r["total"] == 1 and r["ultimas_24h"] == 0 and r["total_30d"] == 1


# ----------------------------------------------------------------------------- túnel


class _Resp:
    def __init__(self, data, ok=True):
        self._d, self._ok = data, ok

    def raise_for_status(self):
        if not self._ok:
            raise RuntimeError("http")

    def json(self):
        return self._d


def test_link_do_tunel_aleatorio():
    s = _settings(tunnel_metrics_url="http://tunnel:2000")
    chamadas = []

    def get(url, timeout):
        chamadas.append((url, timeout))
        return _Resp({"hostname": "Roda-Livre-1234.trycloudflare.com"})

    r = descobrir_link(s, get)
    assert r == {"url": "https://roda-livre-1234.trycloudflare.com", "aleatorio": True, "estado": "ativo"}
    assert chamadas == [("http://tunnel:2000/quicktunnel", 2)]


@pytest.mark.parametrize(
    "resposta, estado",
    [
        (_Resp({"hostname": ""}), "aguardando o túnel iniciar"),
        (_Resp({}), "aguardando o túnel iniciar"),
        (_Resp({"hostname": "x.com/../evil?"}), "endereço do túnel inválido"),
        (_Resp({"hostname": "a b.com"}), "endereço do túnel inválido"),
        (_Resp({}, ok=False), "túnel indisponível"),
    ],
)
def test_link_do_tunel_estados(resposta, estado):
    r = descobrir_link(_settings(tunnel_metrics_url="http://t:2000"), lambda url, timeout: resposta)
    assert r["url"] is None and r["estado"] == estado


def test_link_do_tunel_falha_de_rede():
    def get(url, timeout):
        raise ConnectionError("sem rota")

    assert descobrir_link(_settings(tunnel_metrics_url="http://t:2000"), get)["estado"] == "túnel indisponível"


def test_link_fixo_e_sem_tunel():
    fixo = descobrir_link(_settings(public_url="https://api.exemplo.org", tunnel_metrics_url="http://t:2000"))
    assert fixo == {"url": "https://api.exemplo.org", "aleatorio": False, "estado": "fixo (PUBLIC_URL)"}
    assert descobrir_link(_settings())["estado"] == "túnel não configurado"


def test_qr_do_link(make_painel):
    c = make_painel(public_url="https://api.exemplo.org")
    r = c.get("/api/qr.svg")
    assert r.status_code == 200 and r.headers["content-type"].startswith("image/svg+xml")
    assert "<svg" in r.text
    assert make_painel().get("/api/qr.svg").status_code == 404


# ------------------------------------------------------- origem do envio (limite)


def _enviar_de(c, ip):
    h = {"CF-Connecting-IP": ip} if ip else {}
    return c.post("/respostas", json=payload(), headers=h).status_code


def test_limite_por_ip_real_quando_confia_no_cloudflare(engine):
    app = create_app(_settings(rate_limit_per_min=1, trust_cf_connecting_ip=True), engine)
    with TestClient(app) as c:
        assert _enviar_de(c, "203.0.113.1") == 201
        assert _enviar_de(c, "203.0.113.1") == 429
        assert _enviar_de(c, "203.0.113.2") == 201  # outra pessoa, outra cota


def test_sem_confiar_o_cabecalho_e_ignorado(engine):
    app = create_app(_settings(rate_limit_per_min=1, trust_cf_connecting_ip=False), engine)
    with TestClient(app) as c:
        assert _enviar_de(c, "203.0.113.1") == 201
        assert _enviar_de(c, "203.0.113.2") == 429  # forjar o cabeçalho não ganha cota nova
