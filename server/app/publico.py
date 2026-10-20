"""Painel PÚBLICO: dados agregados e anonimizados, de livre visualização (sem senha).

Regras de privacidade (as mesmas prometidas no termo de LGPD do app):
- NUNCA devolve respostas individuais, `submission_id`, hora exata de um envio nem coordenadas
  além da célula de ~1 km.
- Abaixo de `min_respostas_publicas` respostas no período, devolve só o total.
- Uma área do mapa só aparece com `min_respostas_celula` respostas ou mais.
- Contagens pequenas (de 1 até `min_respostas_celula` - 1) de perfil e de contexto viram `None`
  (a tela mostra "menos de N"). Um campo de contexto com poucas respostas é omitido por inteiro.

O que NÃO é público: lista das últimas respostas, mapa por resposta, exportação CSV e o painel
do administrador (`app.painel`, com token).
"""

from __future__ import annotations

import datetime as dt
from typing import Any

from sqlalchemy import case, func, select
from sqlalchemy.orm import Session

from . import bairros, stats
from .config import Settings
from .models import Resposta
from .rotulos import SINTOMA_ROTULOS
from .schemas import CONTEXTO_CAMPOS

#: Períodos aceitos (em dias). Limitar evita encher o cache com valores arbitrários.
PERIODOS = (1, 7, 30, 90)

_PERFIS = ("idoso", "gestante", "crianca", "doenca_respiratoria", "doenca_cardiaca")


def _ocultar(n: int, minimo: int) -> int | None:
    """Contagem pequena (maior que zero e abaixo do mínimo) não é divulgada."""
    return None if 0 < n < minimo else n


def montar(session: Session, settings: Settings, dias: int, agora: dt.datetime | None = None) -> dict[str, Any]:
    agora = agora or dt.datetime.now(dt.timezone.utc)
    est = stats.calcular(session, dias=dias, minimo=settings.min_respostas_publicas, agora=agora)
    base: dict[str, Any] = {
        "gerado_em": agora.isoformat(),
        "periodo_dias": dias,
        "total_respostas": est.total_respostas,
        "suficiente": est.suficiente,
        "minimo_para_divulgar": settings.min_respostas_publicas,
        "minimo_por_area": settings.min_respostas_celula,
    }
    if not est.suficiente:
        base["faltam"] = settings.min_respostas_publicas - est.total_respostas
        return base

    desde = agora - dt.timedelta(days=dias)
    minimo = settings.min_respostas_celula

    perfil_row = session.execute(
        select(*[func.sum(case((getattr(Resposta, p), 1), else_=0)) for p in _PERFIS]).where(
            Resposta.criado_em >= desde
        )
    ).one()
    perfil = {p: _ocultar(int(v or 0), minimo) for p, v in zip(_PERFIS, perfil_row)}

    exposicao = {"under1h": 0, "between1and4h": 0, "over4h": 0}
    for valor, qtd in session.execute(
        select(Resposta.exposicao, func.count()).where(Resposta.criado_em >= desde).group_by(Resposta.exposicao)
    ):
        exposicao[valor] = int(qtd)
    exposicao = {k: _ocultar(v, minimo) for k, v in exposicao.items()}

    contagem: dict[str, dict[str, int]] = {c: {} for c in CONTEXTO_CAMPOS}
    for (ctx,) in session.execute(select(Resposta.contexto).where(Resposta.criado_em >= desde)):
        for campo, valor in (ctx or {}).items():
            if campo in contagem:
                chave = ("sim" if valor else "nao") if isinstance(valor, bool) else str(valor)
                contagem[campo][chave] = contagem[campo].get(chave, 0) + 1
    contexto: dict[str, Any] = {}
    for campo, valores in contagem.items():
        respondeu = sum(valores.values())
        if respondeu < minimo:
            continue  # poucas respostas: o campo inteiro fica de fora
        contexto[campo] = {
            "respondeu": respondeu,
            "valores": {k: _ocultar(v, minimo) for k, v in sorted(valores.items())},
        }

    mapa = stats.mapa(session, horas=min(dias * 24, 24 * 30), minimo_celula=minimo, agora=agora)

    base.update(
        {
            "niveis": est.niveis,
            "sintomas": [
                {
                    "id": s.sintoma,
                    "rotulo": SINTOMA_ROTULOS.get(s.sintoma, s.sintoma),
                    "relatos": s.relatos,
                    "percentual": s.percentual,
                    "leve": s.leve,
                    "moderado": s.moderado,
                    "intenso": s.intenso,
                    "gravidade_media": s.gravidade_media,
                }
                for s in est.sintomas
            ],
            "serie_diaria": [{"dia": d.dia.isoformat(), "respostas": d.respostas} for d in est.serie],
            "bairros": bairros.ranking(session, settings, dias, agora),
            "perfil": perfil,
            "exposicao": exposicao,
            "contexto": contexto,
            "mapa": {
                "horas": mapa.horas,
                "celulas": [c.model_dump() for c in mapa.celulas],
            },
        }
    )
    return base
