import datetime as dt
import uuid

from sqlalchemy.orm import Session

from app.models import Resposta, RespostaSintoma

from .conftest import payload


def _enviar(client, lat, lon, nivel="low"):
    r = client.post("/respostas", json=payload(lat=lat, lon=lon, nivel=nivel))
    assert r.status_code == 201


def test_celula_com_poucas_respostas_nao_aparece(client):
    # Mínimo por célula = 3: duas respostas no mesmo lugar não aparecem.
    _enviar(client, -3.119, -60.021)
    _enviar(client, -3.121, -60.019)
    dados = client.get("/mapa").json()
    assert dados["celulas"] == []
    assert dados["minimo_por_celula"] == 3


def test_celula_agrupa_pelo_arredondamento_e_mostra_o_pior_nivel(client):
    # Três respostas arredondam para (-3.12, -60.02): níveis low, high, moderate -> pior = high.
    _enviar(client, -3.119, -60.021, "low")
    _enviar(client, -3.121, -60.019, "high")
    _enviar(client, -3.122, -60.018, "moderate")
    # Outra célula, só com 1 resposta: fica oculta.
    _enviar(client, -4.5, -61.0, "emergency")

    dados = client.get("/mapa?horas=72").json()
    assert len(dados["celulas"]) == 1
    celula = dados["celulas"][0]
    assert (celula["lat"], celula["lon"]) == (-3.12, -60.02)
    assert celula["respostas"] == 3
    assert celula["pior_nivel"] == "high"


def test_respostas_sem_localizacao_nao_entram_no_mapa(client):
    for _ in range(4):
        body = payload()
        body.pop("lat")
        body.pop("lon")
        assert client.post("/respostas", json=body).status_code == 201
    assert client.get("/mapa").json()["celulas"] == []


def test_janela_de_horas_exclui_respostas_antigas(client, engine):
    antiga = dt.datetime.now(dt.timezone.utc) - dt.timedelta(hours=100)
    with Session(engine) as s:
        for _ in range(3):
            s.add(
                Resposta(
                    submission_id=uuid.uuid4(),
                    criado_em=antiga,
                    registrado_em=antiga,
                    lat=-3.12,
                    lon=-60.02,
                    nivel="low",
                    pontos=1,
                    exposicao="under1h",
                    sintomas=[RespostaSintoma(sintoma="cough", gravidade=1)],
                )
            )
        s.commit()
    assert client.get("/mapa?horas=72").json()["celulas"] == []
    assert len(client.get("/mapa?horas=200").json()["celulas"]) == 1


def test_parametro_horas_validado(client):
    assert client.get("/mapa?horas=0").status_code == 422
    assert client.get("/mapa?horas=100000").status_code == 422
