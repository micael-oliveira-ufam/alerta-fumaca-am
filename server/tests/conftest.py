"""Fixtures. Por padrão usa SQLite em memória; defina TEST_DATABASE_URL para testar no PostgreSQL:

    TEST_DATABASE_URL=postgresql+psycopg://user:senha@localhost:5432/alerta_test pytest
"""

import datetime as dt
import os
import sys
import uuid
import warnings
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.exc import SAWarning

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.config import Settings  # noqa: E402
from app.db import make_engine  # noqa: E402
from app.main import create_app  # noqa: E402
from app.models import Base  # noqa: E402

TEST_DB = os.getenv("TEST_DATABASE_URL", "sqlite://")

# SQLite não tem Decimal nativo; o aviso é esperado e não afeta o teste.
warnings.filterwarnings("ignore", category=SAWarning)


@pytest.fixture()
def engine():
    eng = make_engine(TEST_DB)
    Base.metadata.drop_all(eng)
    Base.metadata.create_all(eng)
    yield eng
    Base.metadata.drop_all(eng)
    eng.dispose()


@pytest.fixture()
def make_client(engine):
    """Fábrica de clientes: aceita sobrescrever configurações (ex.: rate_limit_per_min)."""
    opened = []

    def _make(**overrides) -> TestClient:
        params = dict(
            database_url=TEST_DB,
            cache_seconds=300,
            cache_max_entries=24,
            rate_limit_per_min=0,
            min_respostas_publicas=5,
            min_respostas_celula=3,
            admin_token="",
            geocoder_ativo=False,
        )
        params.update(overrides)
        client = TestClient(create_app(Settings(**params), engine))
        client.__enter__()  # executa o lifespan (cria as tabelas)
        opened.append(client)
        return client

    yield _make
    for c in opened:
        c.__exit__(None, None, None)


@pytest.fixture()
def client(make_client):
    return make_client()


def payload(**over) -> dict:
    """Resposta válida; cada chamada gera um submission_id novo."""
    base = {
        "submission_id": str(uuid.uuid4()),
        "registrado_em": dt.datetime.now(dt.timezone.utc).isoformat(),
        "lat": -3.119,
        "lon": -60.0217,
        "nivel": "moderate",
        "pontos": 9,
        "exposicao": "between1and4h",
        "perfil": {"idoso": False, "gestante": True},
        "sintomas": {"cough": 2, "headache": 1, "dyspnea": 0},
        "app_version": "1.0.0",
    }
    base.update(over)
    return base
