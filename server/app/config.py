"""Configuração lida de variáveis de ambiente (12-factor)."""

from __future__ import annotations

import os
from dataclasses import dataclass

from sqlalchemy import URL


def _int(name: str, default: int) -> int:
    raw = os.getenv(name, "").strip()
    return int(raw) if raw else default


def database_url_from_env() -> str | URL:
    """`DATABASE_URL` tem prioridade; senão monta a URL a partir de POSTGRES_*.

    Montar por partes evita erro quando a senha tem caracteres como `@` ou `/`:
    `URL.create` faz o escape corretamente.
    """
    explicit = os.getenv("DATABASE_URL", "").strip()
    if explicit:
        return explicit
    return URL.create(
        "postgresql+psycopg",
        username=os.getenv("POSTGRES_USER", "alerta"),
        password=os.getenv("POSTGRES_PASSWORD", "alerta_dev"),
        host=os.getenv("POSTGRES_HOST", "localhost"),
        port=_int("POSTGRES_PORT", 5432),
        database=os.getenv("POSTGRES_DB", "alerta"),
    )


@dataclass(frozen=True)
class Settings:
    database_url: str | URL

    #: Tempo (s) em que uma resposta do INPE é reaproveitada sem nova consulta.
    cache_seconds: int = 300

    #: Máximo de respostas do INPE guardadas em memória (limita o uso de RAM).
    cache_max_entries: int = 24

    #: Envios por minuto por origem em POST /respostas. 0 desativa o limite.
    rate_limit_per_min: int = 30

    #: Abaixo deste número de respostas no período, as estatísticas não são
    #: divulgadas (evita expor registros individuais em amostras minúsculas).
    min_respostas_publicas: int = 5

    #: Uma área (célula de ~1 km) só aparece no mapa coletivo com pelo menos este
    #: número de respostas no período. Impede mostrar a localização de uma pessoa só.
    min_respostas_celula: int = 3

    #: Token do endpoint de exportação CSV. Vazio = exportação desativada.
    admin_token: str = ""

    @classmethod
    def from_env(cls) -> "Settings":
        return cls(
            database_url=database_url_from_env(),
            cache_seconds=_int("INPE_CACHE_SECONDS", 300),
            cache_max_entries=_int("INPE_CACHE_MAX_ENTRIES", 24),
            rate_limit_per_min=_int("RATE_LIMIT_PER_MIN", 30),
            min_respostas_publicas=_int("MIN_RESPOSTAS_PUBLICAS", 5),
            min_respostas_celula=_int("MIN_RESPOSTAS_CELULA", 3),
            admin_token=os.getenv("ADMIN_TOKEN", "").strip(),
        )
