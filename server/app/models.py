"""Modelo de dados (PostgreSQL; também roda em SQLite nos testes).

Privacidade (LGPD) — decisões de projeto:
- NÃO há coluna de nome, telefone, e-mail, endereço IP ou identificador de aparelho.
- `submission_id` é um UUID aleatório gerado PARA CADA ENVIO (não para cada
  aparelho). Serve só para o reenvio após falha de rede não duplicar o registro.
- A coordenada é guardada com 2 casas decimais (~1,1 km), mesmo que o cliente
  envie mais precisão (o arredondamento também é refeito no servidor).
- Respostas de sintomas e o perfil (gestante, idoso etc.) são dados de saúde:
  só devem ser enviados com consentimento específico, coletado no app.
"""

from __future__ import annotations

import datetime as dt
import uuid
from decimal import Decimal

from sqlalchemy import (
    BigInteger,
    Boolean,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    Numeric,
    SmallInteger,
    JSON,
    String,
    Uuid,
    func,
)
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship

NIVEIS = ("low", "moderate", "high", "emergency")
EXPOSICOES = ("under1h", "between1and4h", "over4h")

# BigInteger vira INTEGER no SQLite para o autoincremento funcionar nos testes.
_BigId = BigInteger().with_variant(Integer, "sqlite")


class Base(DeclarativeBase):
    pass


class Resposta(Base):
    __tablename__ = "respostas"
    __table_args__ = (
        CheckConstraint("nivel IN ('low','moderate','high','emergency')", name="ck_respostas_nivel"),
        CheckConstraint(
            "exposicao IN ('under1h','between1and4h','over4h')", name="ck_respostas_exposicao"
        ),
        CheckConstraint("pontos >= 0", name="ck_respostas_pontos"),
        Index("ix_respostas_criado_em", "criado_em"),
    )

    id: Mapped[int] = mapped_column(_BigId, primary_key=True, autoincrement=True)
    submission_id: Mapped[uuid.UUID] = mapped_column(Uuid, unique=True, nullable=False)

    #: Hora do servidor ao receber (base das estatísticas; não depende do relógio do aparelho).
    criado_em: Mapped[dt.datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    #: Hora informada pelo aparelho (apenas informativa).
    registrado_em: Mapped[dt.datetime] = mapped_column(DateTime(timezone=True), nullable=False)

    lat: Mapped[Decimal | None] = mapped_column(Numeric(5, 2), nullable=True)
    lon: Mapped[Decimal | None] = mapped_column(Numeric(5, 2), nullable=True)

    nivel: Mapped[str] = mapped_column(String(16), nullable=False)
    pontos: Mapped[int] = mapped_column(SmallInteger, nullable=False)
    exposicao: Mapped[str] = mapped_column(String(16), nullable=False)

    idoso: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    gestante: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    crianca: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    doenca_respiratoria: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    doenca_cardiaca: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)

    app_version: Mapped[str | None] = mapped_column(String(32), nullable=True)

    #: Contexto da exposição e da saúde de base (local, máscara, medicação...), só as chaves
    #: respondidas. Ver `Contexto` em schemas.py. Nulo em respostas de versões antigas do app.
    contexto: Mapped[dict | None] = mapped_column(JSON, nullable=True)

    sintomas: Mapped[list["RespostaSintoma"]] = relationship(
        back_populates="resposta", cascade="all, delete-orphan"
    )


class CelulaBairro(Base):
    """Cache do bairro de cada célula de ~1 km (nome obtido do OpenStreetMap/Nominatim).

    Não guarda nada de usuários: só a relação "célula -> bairro". `bairro` nulo = o geocodificador
    respondeu, mas sem bairro (a célula não é reconsultada).
    """

    __tablename__ = "celulas_bairro"

    lat: Mapped[Decimal] = mapped_column(Numeric(5, 2), primary_key=True)
    lon: Mapped[Decimal] = mapped_column(Numeric(5, 2), primary_key=True)
    bairro: Mapped[str | None] = mapped_column(String(120), nullable=True)
    cidade: Mapped[str | None] = mapped_column(String(80), nullable=True)
    resolvido_em: Mapped[dt.datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )


class RespostaSintoma(Base):
    __tablename__ = "respostas_sintomas"
    __table_args__ = (
        CheckConstraint("gravidade BETWEEN 0 AND 3", name="ck_sintomas_gravidade"),
        Index("ix_respostas_sintomas_sintoma", "sintoma"),
    )

    resposta_id: Mapped[int] = mapped_column(
        _BigId, ForeignKey("respostas.id", ondelete="CASCADE"), primary_key=True
    )
    #: Identificador do sintoma no app (ex.: "cough", "dyspnea").
    sintoma: Mapped[str] = mapped_column(String(32), primary_key=True)
    #: 0 = nenhum, 1 = leve, 2 = moderado, 3 = intenso.
    gravidade: Mapped[int] = mapped_column(SmallInteger, nullable=False)

    resposta: Mapped[Resposta] = relationship(back_populates="sintomas")
