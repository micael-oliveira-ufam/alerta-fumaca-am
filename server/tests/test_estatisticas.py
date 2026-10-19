import datetime as dt

from sqlalchemy.orm import Session

from app.models import Resposta, RespostaSintoma

from .conftest import payload


def _enviar(client, sintomas, nivel="moderate"):
    r = client.post("/respostas", json=payload(sintomas=sintomas, nivel=nivel))
    assert r.status_code == 201


def test_abaixo_do_minimo_nao_divulga_detalhes(client):
    for _ in range(4):  # mínimo configurado = 5
        _enviar(client, {"cough": 3})
    r = client.get("/estatisticas")
    assert r.status_code == 200
    dados = r.json()
    assert dados["total_respostas"] == 4
    assert dados["suficiente"] is False
    assert dados["sintomas"] == [] and dados["serie"] == []
    assert dados["minimo_para_divulgar"] == 5


def test_sintomas_mais_relatados_com_contagens_exatas(client):
    # 6 respostas. Tosse: 5 relatos (gravidades 3,2,2,1,1) e 1 sem. Dor de cabeça: 2 relatos.
    _enviar(client, {"cough": 3, "headache": 2})
    _enviar(client, {"cough": 2, "headache": 1})
    _enviar(client, {"cough": 2})
    _enviar(client, {"cough": 1})
    _enviar(client, {"cough": 1})
    _enviar(client, {"cough": 0, "eyes": 0})

    dados = client.get("/estatisticas?dias=30").json()
    assert dados["suficiente"] is True and dados["total_respostas"] == 6

    por_nome = {s["sintoma"]: s for s in dados["sintomas"]}
    tosse = por_nome["cough"]
    assert tosse["relatos"] == 5
    assert tosse["percentual"] == 83.3  # 5/6
    assert (tosse["leve"], tosse["moderado"], tosse["intenso"]) == (2, 2, 1)
    assert tosse["gravidade_media"] == 1.8  # (3+2+2+1+1)/5

    cabeca = por_nome["headache"]
    assert cabeca["relatos"] == 2 and cabeca["percentual"] == 33.3
    assert cabeca["gravidade_media"] == 1.5

    # Sintoma só com gravidade 0: aparece, mas com 0 relatos e sem média.
    assert por_nome["eyes"]["relatos"] == 0 and por_nome["eyes"]["gravidade_media"] is None

    # Ordenado do mais para o menos relatado.
    nomes = [s["sintoma"] for s in dados["sintomas"]]
    assert nomes.index("cough") < nomes.index("headache") < nomes.index("eyes")


def test_distribuicao_por_nivel_e_serie_diaria(client):
    for nivel in ["low", "low", "high", "emergency", "moderate", "moderate"]:
        _enviar(client, {"cough": 1}, nivel=nivel)
    dados = client.get("/estatisticas").json()
    assert dados["niveis"] == {"low": 2, "moderate": 2, "high": 1, "emergency": 1}
    assert sum(d["respostas"] for d in dados["serie"]) == 6
    assert len(dados["serie"]) == 1  # todas enviadas hoje
    # O dia segue o fuso da sessão do banco (UTC no contêiner padrão, mas pode ser outro em
    # instalações locais). Por isso a tolerância de ±1 dia perto da virada do dia UTC.
    dia = dt.date.fromisoformat(dados["serie"][0]["dia"])
    assert abs((dia - dt.datetime.now(dt.timezone.utc).date()).days) <= 1


def test_periodo_exclui_respostas_antigas(client, engine):
    for _ in range(5):
        _enviar(client, {"cough": 2})
    # Uma resposta antiga, inserida direto com criado_em de 60 dias atrás.
    antiga = dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=60)
    with Session(engine) as s:
        s.add(
            Resposta(
                submission_id=__import__("uuid").uuid4(),
                criado_em=antiga,
                registrado_em=antiga,
                nivel="low",
                pontos=1,
                exposicao="under1h",
                sintomas=[RespostaSintoma(sintoma="cough", gravidade=3)],
            )
        )
        s.commit()

    assert client.get("/estatisticas?dias=30").json()["total_respostas"] == 5
    assert client.get("/estatisticas?dias=90").json()["total_respostas"] == 6


def test_parametro_dias_validado(client):
    assert client.get("/estatisticas?dias=0").status_code == 422
    assert client.get("/estatisticas?dias=366").status_code == 422
