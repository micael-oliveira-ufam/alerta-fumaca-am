"""Estatísticas agregadas das respostas (consultas portáveis entre PostgreSQL e SQLite)."""

from __future__ import annotations

import datetime as dt

from sqlalchemy import case, func, select
from sqlalchemy.orm import Session

from .models import NIVEIS, Resposta, RespostaSintoma
from .schemas import CelulaMapa, Estatisticas, MapaColetivo, SerieDia, SintomaStat


def calcular(
    session: Session,
    *,
    dias: int,
    minimo: int,
    agora: dt.datetime | None = None,
) -> Estatisticas:
    """Agrega as respostas dos últimos `dias` dias (pela hora do SERVIDOR).

    Se houver menos de `minimo` respostas, devolve só o total (`suficiente=False`),
    para não expor registros individuais em amostras muito pequenas.
    """
    agora = agora or dt.datetime.now(dt.timezone.utc)
    desde = agora - dt.timedelta(days=dias)

    total = session.scalar(
        select(func.count()).select_from(Resposta).where(Resposta.criado_em >= desde)
    ) or 0

    if total < minimo:
        return Estatisticas(
            periodo_dias=dias,
            total_respostas=total,
            suficiente=False,
            minimo_para_divulgar=minimo,
            niveis={n: 0 for n in NIVEIS},
            sintomas=[],
            serie=[],
        )

    niveis = {n: 0 for n in NIVEIS}
    for nivel, qtd in session.execute(
        select(Resposta.nivel, func.count())
        .where(Resposta.criado_em >= desde)
        .group_by(Resposta.nivel)
    ):
        niveis[nivel] = qtd

    g = RespostaSintoma.gravidade
    relatos = func.sum(case((g >= 1, 1), else_=0))
    sintomas_rows = session.execute(
        select(
            RespostaSintoma.sintoma,
            relatos.label("relatos"),
            func.sum(case((g == 1, 1), else_=0)).label("leve"),
            func.sum(case((g == 2, 1), else_=0)).label("moderado"),
            func.sum(case((g == 3, 1), else_=0)).label("intenso"),
            # AVG ignora NULL: só entram as gravidades >= 1.
            func.avg(case((g >= 1, g))).label("media"),
        )
        .join(Resposta, Resposta.id == RespostaSintoma.resposta_id)
        .where(Resposta.criado_em >= desde)
        .group_by(RespostaSintoma.sintoma)
    ).all()

    sintomas = [
        SintomaStat(
            sintoma=row.sintoma,
            relatos=int(row.relatos or 0),
            percentual=round(100 * int(row.relatos or 0) / total, 1),
            leve=int(row.leve or 0),
            moderado=int(row.moderado or 0),
            intenso=int(row.intenso or 0),
            gravidade_media=None if row.media is None else round(float(row.media), 2),
        )
        for row in sintomas_rows
    ]
    # Mais relatados primeiro; empate resolvido pelo nome (ordem estável).
    sintomas.sort(key=lambda s: (-s.relatos, s.sintoma))

    # func.date() funciona em PostgreSQL e SQLite (CAST AS DATE no SQLite devolve só o ano).
    # O dia segue o fuso da sessão do banco (UTC no contêiner postgres padrão).
    dia = func.date(Resposta.criado_em)
    serie = [
        SerieDia(dia=_como_data(d), respostas=qtd)
        for d, qtd in session.execute(
            select(dia, func.count()).where(Resposta.criado_em >= desde).group_by(dia).order_by(dia)
        )
    ]

    return Estatisticas(
        periodo_dias=dias,
        total_respostas=total,
        suficiente=True,
        minimo_para_divulgar=minimo,
        niveis=niveis,
        sintomas=sintomas,
        serie=serie,
    )


def mapa(
    session: Session,
    *,
    horas: int,
    minimo_celula: int,
    agora: dt.datetime | None = None,
) -> MapaColetivo:
    """Células de ~1 km com respostas nas últimas `horas`, ocultando as pouco povoadas.

    A coordenada já é gravada com 2 casas decimais, então cada par (lat, lon) é uma célula.
    Células com menos de `minimo_celula` respostas não são devolvidas (privacidade).
    """
    agora = agora or dt.datetime.now(dt.timezone.utc)
    desde = agora - dt.timedelta(hours=horas)

    # Posição do nível na escala de gravidade (para obter o pior nível de cada célula).
    rank = case(
        (Resposta.nivel == "emergency", 3),
        (Resposta.nivel == "high", 2),
        (Resposta.nivel == "moderate", 1),
        else_=0,
    )
    pior_por_rank = {0: "low", 1: "moderate", 2: "high", 3: "emergency"}

    rows = session.execute(
        select(Resposta.lat, Resposta.lon, func.count(), func.max(rank))
        .where(
            Resposta.criado_em >= desde,
            Resposta.lat.is_not(None),
            Resposta.lon.is_not(None),
        )
        .group_by(Resposta.lat, Resposta.lon)
        .having(func.count() >= minimo_celula)
        .order_by(Resposta.lat, Resposta.lon)
    ).all()

    return MapaColetivo(
        horas=horas,
        minimo_por_celula=minimo_celula,
        celulas=[
            CelulaMapa(
                lat=float(lat),
                lon=float(lon),
                respostas=int(qtd),
                pior_nivel=pior_por_rank[int(maximo)],
            )
            for lat, lon, qtd, maximo in rows
        ],
    )


def _como_data(valor: object) -> dt.date:
    # SQLite devolve texto ("2026-10-19"); PostgreSQL devolve date.
    if isinstance(valor, dt.datetime):
        return valor.date()
    if isinstance(valor, dt.date):
        return valor
    return dt.date.fromisoformat(str(valor))
