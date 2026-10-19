"""Criação do engine e da sessão."""

from __future__ import annotations

import logging
import time

from sqlalchemy import URL, Engine, create_engine, text
from sqlalchemy.exc import OperationalError
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from .models import Base

log = logging.getLogger("alerta.db")


def make_engine(url: str | URL) -> Engine:
    rendered = url if isinstance(url, str) else url.render_as_string(hide_password=False)
    if rendered.startswith("sqlite"):
        # SQLite em memória (testes): uma única conexão compartilhada entre threads.
        return create_engine(
            url,
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )
    return create_engine(url, pool_pre_ping=True)


def init_schema(engine: Engine, attempts: int = 15, wait_s: float = 2.0) -> None:
    """Cria as tabelas se não existirem (idempotente).

    No Docker o banco pode demorar alguns segundos para aceitar conexões; por isso
    há novas tentativas antes de desistir.
    """
    for attempt in range(1, attempts + 1):
        try:
            with engine.connect() as conn:
                conn.execute(text("SELECT 1"))
            Base.metadata.create_all(engine)
            return
        except OperationalError as exc:
            if attempt == attempts:
                raise
            log.warning("Banco indisponível (%s/%s): %s", attempt, attempts, exc.__class__.__name__)
            time.sleep(wait_s)


def make_session_factory(engine: Engine) -> sessionmaker[Session]:
    return sessionmaker(engine, expire_on_commit=False)
