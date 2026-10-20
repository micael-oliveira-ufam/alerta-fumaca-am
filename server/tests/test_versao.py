"""A versão exibida pela API deve ser a do arquivo VERSION (fonte única do projeto)."""

from pathlib import Path

from app.main import APP_VERSION

RAIZ = Path(__file__).resolve().parents[2]


def test_app_version_bate_com_VERSION():
    esperado = (RAIZ / "VERSION").read_text(encoding="utf-8").strip()
    assert APP_VERSION == esperado


def test_health_expoe_a_versao(client):
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json()["version"] == APP_VERSION
