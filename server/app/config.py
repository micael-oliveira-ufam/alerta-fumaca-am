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

    #: Token do endpoint de exportação CSV e do painel. Vazio = exportação desativada.
    admin_token: str = ""

    #: Usar o cabeçalho `CF-Connecting-IP` (Cloudflare) como origem no limitador de envios.
    #: Ative SOMENTE se a API só for alcançável pelo túnel (senão o cabeçalho pode ser forjado).
    trust_cf_connecting_ip: bool = False

    #: Descobrir o bairro de Manaus de cada célula de ~1 km pelo OpenStreetMap (Nominatim).
    #: Só coordenadas já arredondadas (~1 km) e sem qualquer identificação são consultadas.
    geocoder_ativo: bool = True

    #: Servidor de geocodificação reversa compatível com o Nominatim.
    geocoder_url: str = "https://nominatim.openstreetmap.org"

    #: Contato enviado no User-Agent, como exige a política de uso do Nominatim.
    geocoder_contato: str = "micael.oliveira@ufam.edu.br"

    #: Endereço público fixo da API (túnel nomeado). Vazio = detectar o link aleatório do túnel.
    public_url: str = ""

    #: Servidor de métricas do `cloudflared`, de onde se lê o link do túnel rápido.
    tunnel_metrics_url: str = ""

    #: Pasta (dentro do contêiner) onde está o APK para download (`Alerta-Fumaca-AM.apk`).
    apk_dir: str = "/srv/dist"
    #: Busca os focos do INPE em segundo plano a cada `cache_seconds` (a página abre já com dados).
    focos_preaquecer: bool = False
    #: Versão mínima do app (X.Y.Z). Abaixo dela o app mostra aviso de atualização obrigatória.
    app_versao_minima: str = ""

    #: Consultar a qualidade do ar (Open-Meteo/CAMS) para a seção do painel público.
    qualidade_ar_ativa: bool = True

    #: Segundos em que a consulta de qualidade do ar é reaproveitada (protege a cota gratuita).
    qualidade_ar_cache_seconds: int = 1800

    #: Endereço da API de qualidade do ar (configurável para testes).
    qualidade_ar_url: str = "https://air-quality-api.open-meteo.com/v1/air-quality"

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
            trust_cf_connecting_ip=os.getenv("TRUST_CF_CONNECTING_IP", "").strip().lower()
            in ("1", "true", "yes", "sim"),
            geocoder_ativo=os.getenv("GEOCODER_ATIVO", "true").strip().lower() in ("1", "true", "yes", "sim"),
            geocoder_url=os.getenv("GEOCODER_URL", "https://nominatim.openstreetmap.org").strip().rstrip("/"),
            geocoder_contato=os.getenv("GEOCODER_CONTATO", "micael.oliveira@ufam.edu.br").strip(),
            public_url=os.getenv("PUBLIC_URL", "").strip().rstrip("/"),
            tunnel_metrics_url=os.getenv("TUNNEL_METRICS_URL", "").strip().rstrip("/"),
            apk_dir=os.getenv("APK_DIR", "/srv/dist").strip() or "/srv/dist",
            focos_preaquecer=os.getenv("FOCOS_PREAQUECER", "false").strip().lower() in ("1", "true", "yes", "sim"),
            app_versao_minima=os.getenv("APP_VERSAO_MINIMA", "").strip(),
            qualidade_ar_ativa=os.getenv("QUALIDADE_AR_ATIVA", "true").strip().lower() in ("1", "true", "yes", "sim"),
            qualidade_ar_cache_seconds=_int("QUALIDADE_AR_CACHE_SECONDS", 1800),
            qualidade_ar_url=os.getenv("QUALIDADE_AR_URL", "https://air-quality-api.open-meteo.com/v1/air-quality").strip(),
        )
