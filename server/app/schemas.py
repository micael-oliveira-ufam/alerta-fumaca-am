"""Contratos da API (entrada e saída), com validação estrita."""

from __future__ import annotations

import datetime as dt
import re
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

SINTOMA_ID = re.compile(r"^[a-z][a-z0-9_]{1,31}$")
MAX_SINTOMAS = 40


def coarsen(value: float) -> float:
    """Arredonda para 2 casas (~1,1 km). Mesma regra do app (`SmokeReport.coarsen`)."""
    return round(value, 2)


class Perfil(BaseModel):
    model_config = ConfigDict(extra="forbid")

    idoso: bool = False
    gestante: bool = False
    crianca: bool = False
    doenca_respiratoria: bool = False
    doenca_cardiaca: bool = False


class Contexto(BaseModel):
    """Contexto da exposição e da saúde de base. Todos os campos são opcionais (sem resposta = ausente)."""

    model_config = ConfigDict(extra="forbid")

    local: Literal["ar_livre", "casa_janelas_abertas", "casa_janelas_fechadas"] | None = None
    fumaca_visivel: bool | None = None
    mascara: Literal["nao_saiu", "nao", "cirurgica_pano", "pff2_n95"] | None = None
    atividade_fisica_ar_livre: bool | None = None
    ar_filtrado: bool | None = None
    trabalho_ar_livre: bool | None = None
    imunologica: bool | None = None
    medicacao_a_mao: bool | None = None
    medicacao_nao_alivia: bool | None = None
    piorando: bool | None = None


CONTEXTO_CAMPOS = tuple(Contexto.model_fields)


class RespostaIn(BaseModel):
    """Uma resposta completa do questionário. Nenhum campo identifica a pessoa."""

    model_config = ConfigDict(extra="forbid")

    submission_id: UUID
    registrado_em: dt.datetime
    lat: float | None = Field(default=None, ge=-90, le=90)
    lon: float | None = Field(default=None, ge=-180, le=180)
    nivel: Literal["low", "moderate", "high", "emergency"]
    pontos: int = Field(ge=0, le=500)
    exposicao: Literal["under1h", "between1and4h", "over4h"]
    perfil: Perfil = Field(default_factory=Perfil)
    sintomas: dict[str, int]
    app_version: str | None = Field(default=None, max_length=32)
    contexto: Contexto | None = None

    @field_validator("sintomas")
    @classmethod
    def _validar_sintomas(cls, value: dict[str, int]) -> dict[str, int]:
        if not 1 <= len(value) <= MAX_SINTOMAS:
            raise ValueError(f"informe de 1 a {MAX_SINTOMAS} sintomas")
        for key, gravidade in value.items():
            if not SINTOMA_ID.match(key):
                raise ValueError(f"identificador de sintoma inválido: {key!r}")
            if not 0 <= gravidade <= 3:
                raise ValueError(f"gravidade de {key!r} deve estar entre 0 e 3")
        return value

    @field_validator("registrado_em")
    @classmethod
    def _exigir_fuso(cls, value: dt.datetime) -> dt.datetime:
        if value.tzinfo is None:
            raise ValueError("registrado_em deve incluir fuso horário (ex.: ...Z)")
        return value

    @model_validator(mode="after")
    def _lat_lon_juntas(self) -> "RespostaIn":
        if (self.lat is None) != (self.lon is None):
            raise ValueError("envie lat e lon juntas, ou nenhuma das duas")
        return self


class RespostaOut(BaseModel):
    id: int
    duplicado: bool = False


class SintomaStat(BaseModel):
    sintoma: str
    #: Respostas em que o sintoma foi relatado (gravidade >= 1).
    relatos: int
    #: relatos / total de respostas do período, em %.
    percentual: float
    leve: int
    moderado: int
    intenso: int
    #: Média da gravidade entre quem relatou (1 a 3).
    gravidade_media: float | None


class SerieDia(BaseModel):
    dia: dt.date
    respostas: int


class CelulaMapa(BaseModel):
    #: Centro da célula (coordenada já arredondada a 2 casas, ~1,1 km).
    lat: float
    lon: float
    respostas: int
    #: Pior nível de risco entre as respostas da célula.
    pior_nivel: Literal["low", "moderate", "high", "emergency"]


class MapaColetivo(BaseModel):
    horas: int
    minimo_por_celula: int
    celulas: list[CelulaMapa]


class Estatisticas(BaseModel):
    periodo_dias: int
    total_respostas: int
    #: False quando há menos respostas que o mínimo público: os detalhes são omitidos.
    suficiente: bool
    minimo_para_divulgar: int
    niveis: dict[str, int]
    sintomas: list[SintomaStat]
    serie: list[SerieDia]
