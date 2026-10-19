import datetime as dt
import uuid
from decimal import Decimal

from sqlalchemy import func, select, text
from sqlalchemy.orm import Session

from app.models import Resposta, RespostaSintoma

from .conftest import payload


def _contar(engine, model):
    with Session(engine) as s:
        return s.scalar(select(func.count()).select_from(model))


def test_health_verifica_o_banco(client):
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"


def test_registra_resposta_e_sintomas(client, engine):
    r = client.post("/respostas", json=payload())
    assert r.status_code == 201
    assert r.json()["duplicado"] is False

    assert _contar(engine, Resposta) == 1
    assert _contar(engine, RespostaSintoma) == 3  # inclui o sintoma com gravidade 0
    with Session(engine) as s:
        row = s.scalars(select(Resposta)).one()
        assert row.nivel == "moderate"
        assert row.gestante is True and row.idoso is False
        graus = {x.sintoma: x.gravidade for x in row.sintomas}
        assert graus == {"cough": 2, "headache": 1, "dyspnea": 0}


def test_servidor_refaz_o_arredondamento_da_coordenada(client, engine):
    # Mesmo que o cliente envie coordenada precisa, só ~1,1 km é gravado.
    client.post("/respostas", json=payload(lat=-3.119042, lon=-60.021749))
    with Session(engine) as s:
        # SQL cru, de propósito: ao LER uma coluna Numeric(5,2) no SQLite o SQLAlchemy
        # arredonda sozinho e esconderia um valor bruto gravado com excesso de precisão.
        lat, lon = s.execute(text("SELECT lat, lon FROM respostas")).one()
        assert Decimal(str(lat)) == Decimal("-3.12")
        assert Decimal(str(lon)) == Decimal("-60.02")


def test_aceita_resposta_sem_localizacao(client, engine):
    body = payload()
    body.pop("lat")
    body.pop("lon")
    assert client.post("/respostas", json=body).status_code == 201
    with Session(engine) as s:
        row = s.scalars(select(Resposta)).one()
        assert row.lat is None and row.lon is None


def test_reenvio_com_mesmo_submission_id_nao_duplica(client, engine):
    body = payload()
    first = client.post("/respostas", json=body)
    again = client.post("/respostas", json=body)
    assert first.status_code == 201
    assert again.status_code == 200
    assert again.json() == {"id": first.json()["id"], "duplicado": True}
    assert _contar(engine, Resposta) == 1


def test_rejeita_dados_invalidos(client, engine):
    casos = {
        "gravidade 4": payload(sintomas={"cough": 4}),
        "gravidade negativa": payload(sintomas={"cough": -1}),
        "id de sintoma inválido": payload(sintomas={"Tosse!": 1}),
        "sem sintomas": payload(sintomas={}),
        "nível inventado": payload(nivel="critico"),
        "exposição inventada": payload(exposicao="sempre"),
        "pontos negativos": payload(pontos=-1),
        "lat sem lon": {**payload(), "lon": None},
        "lat fora do intervalo": payload(lat=91),
        "data sem fuso": payload(registrado_em="2026-10-19T10:00:00"),
        "uuid inválido": payload(submission_id="nao-e-uuid"),
        "campo extra (tentativa de enviar identificador)": {**payload(), "telefone": "9299999999"},
        "perfil com campo extra": payload(perfil={"nome": "Fulano"}),
    }
    for nome, corpo in casos.items():
        r = client.post("/respostas", json=corpo)
        assert r.status_code == 422, f"{nome}: esperado 422, veio {r.status_code}"
    assert _contar(engine, Resposta) == 0  # nada inválido foi gravado


def test_limite_de_envios_por_minuto(make_client):
    limitado = make_client(rate_limit_per_min=2)
    codigos = [limitado.post("/respostas", json=payload()).status_code for _ in range(3)]
    assert codigos == [201, 201, 429]


def test_exportacao_desativada_sem_token_configurado(client):
    assert client.get("/respostas/export.csv").status_code == 404


def test_exportacao_exige_token_correto(make_client):
    c = make_client(admin_token="segredo-de-teste")
    assert c.get("/respostas/export.csv").status_code == 401
    assert c.get("/respostas/export.csv", headers={"X-Admin-Token": "errado"}).status_code == 401


def test_exportacao_csv_em_formato_largo(make_client):
    c = make_client(admin_token="segredo-de-teste")
    c.post("/respostas", json=payload(sintomas={"cough": 3, "eyes": 1}))
    c.post("/respostas", json=payload(sintomas={"cough": 0, "headache": 2}))

    r = c.get("/respostas/export.csv", headers={"X-Admin-Token": "segredo-de-teste"})
    assert r.status_code == 200
    assert r.headers["content-type"].startswith("text/csv")
    linhas = r.text.strip().splitlines()
    assert len(linhas) == 3  # cabeçalho + 2 respostas
    cab = linhas[0].split(",")
    assert {"sintoma_cough", "sintoma_eyes", "sintoma_headache"} <= set(cab)
    assert "telefone" not in cab and "ip" not in cab
    primeira = dict(zip(cab, linhas[1].split(",")))
    assert primeira["sintoma_cough"] == "3"
    assert primeira["sintoma_headache"] == ""  # não perguntado nessa resposta
