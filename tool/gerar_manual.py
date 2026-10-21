#!/usr/bin/env python3
"""Gera o manual ilustrado de instalação do RespirAR Amazonas (PDF).

Uso:
  python3 tool/gerar_manual.py                                   # server/app/manual/Manual_Instalacao_RespirAR_Amazonas.pdf
  python3 tool/gerar_manual.py --saida dist/Manual-RespirAR-Amazonas.pdf

Reprodutível: texto e versão vêm deste arquivo e de `VERSION`; as imagens ficam em
`assets/manual/` (splash do app, tela da plataforma e capturas de tela do Android). Requer
`reportlab` e `pillow` (pip install reportlab pillow). O PDF de `dist/` tem prioridade no servidor;
o de `server/app/manual/` é o reserva que acompanha a imagem Docker.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
IMG = RAIZ / "assets" / "manual"
PADRAO = RAIZ / "server" / "app" / "manual" / "Manual_Instalacao_RespirAR_Amazonas.pdf"
SITE = "https://respirar-amazonas.cloud"
ELABORADO_EM = "18 de outubro de 2026"
ATUALIZADO_EM = "20 de outubro de 2026"
AUTORES = ("Micael Davi Lima de Oliveira", "Elias Barros")
VERDE = (0.106, 0.369, 0.125)  # #1B5E20

ETAPAS = [
    ("Abra a plataforma e toque em Baixar",
     "No navegador do celular, abra <b>{site}</b> (ou aponte a câmera para o QR code da página). No quadro "
     "<b>Baixe o aplicativo</b>, toque em <b>Baixar para Android</b>. O arquivo se chama "
     "<b>{apk}</b>: confira o nome e a versão antes de continuar. Se o navegador perguntar, autorize o download.",
     "passo-site.png",
     "Ilustração do quadro de download. O tamanho e a data mostrados na sua tela podem ser diferentes."),
    ("Confirme que o arquivo foi baixado",
     "Abra a pasta <b>Downloads</b> do celular e procure <b>{apk}</b>. Aguarde o download terminar.",
     "passo-downloads.jpg",
     "Captura de uma versão anterior do app: no seu celular o arquivo aparece como {apk}."),
    ("Inicie a instalação",
     "Toque no arquivo APK baixado. Na janela <b>Instalar este app?</b>, confira o nome do aplicativo e toque em "
     "<b>Instalar</b>. Aguarde a conclusão.",
     "passo-instalar.jpg",
     "Captura de uma versão anterior: o nome mostrado hoje é RespirAR Amazonas."),
    ("Leia o aviso do Google Play Protect",
     "O Android pode mostrar um alerta sobre um aplicativo instalado por arquivo APK. Só prossiga se você confia na "
     "origem do arquivo (esta plataforma, fornecida pela equipe responsável). Se tiver dúvida, cancele e confirme a "
     "procedência. <b>Não ignore avisos de segurança sem verificar a origem do aplicativo.</b>",
     "passo-playprotect.jpg", None),
    ("Permita a instalação da fonte, se necessário",
     "Se o Android bloquear a instalação, abra <b>Configurações</b> e procure por <b>Instalar apps desconhecidos</b>. "
     "Selecione o aplicativo que abriu o APK (por exemplo, o navegador ou Meus Arquivos) e permita a instalação "
     "somente para concluir este procedimento. Os nomes dos menus variam por aparelho e versão do Android.",
     "passo-fontes.jpg", None),
    ("Localize as configurações de segurança",
     "Na área de segurança do Android, procure a opção de instalação de aplicativos desconhecidos. Se não encontrar, "
     "use a busca das Configurações e pesquise “instalar apps desconhecidos”. Depois da instalação, desative "
     "novamente essa permissão.",
     "passo-seguranca.jpg", None),
    ("Verifique o aplicativo instalado",
     "Ao terminar, volte à tela inicial ou à lista de aplicativos e procure o ícone do <b>RespirAR Amazonas</b>. "
     "Se não aparecer imediatamente, abra a lista completa de apps. Ao abrir, você verá a tela de abertura mostrada "
     "na primeira página deste manual.",
     "passo-icone.jpg",
     "Captura de uma versão anterior: o ícone e o nome atuais são os da primeira página."),
]


def versao() -> str:
    return (RAIZ / "VERSION").read_text(encoding="utf-8").strip()


def gerar(saida: Path, ver: str | None = None) -> Path:
    from reportlab.lib.pagesizes import A4
    from reportlab.lib.styles import ParagraphStyle
    from reportlab.lib.units import cm
    from reportlab.lib.colors import Color, HexColor
    from reportlab.lib.enums import TA_CENTER
    from reportlab.platypus import BaseDocTemplate, Frame, Image, KeepTogether, PageBreak, PageTemplate, Paragraph, Spacer
    from PIL import Image as PILImage

    ver = ver or versao()
    apk = f"RespirAR-Amazonas-v{ver}.apk"
    verde = Color(*VERDE)
    azul = HexColor("#0B57D0")

    h = ParagraphStyle("h", fontName="Helvetica-Bold", fontSize=14, leading=18, textColor=verde, spaceAfter=6)
    corpo = ParagraphStyle("c", fontName="Helvetica", fontSize=10.5, leading=15, spaceAfter=6)
    nota = ParagraphStyle("n", fontName="Helvetica-Oblique", fontSize=8.5, leading=11, textColor=HexColor("#555555"), alignment=TA_CENTER)
    t1 = ParagraphStyle("t1", fontName="Helvetica-Bold", fontSize=26, leading=30, textColor=verde, alignment=TA_CENTER)
    t2 = ParagraphStyle("t2", fontName="Helvetica", fontSize=11, leading=15, textColor=HexColor("#444444"), alignment=TA_CENTER, spaceAfter=8)
    cen = ParagraphStyle("cen", parent=corpo, alignment=TA_CENTER, spaceAfter=3)

    def rodape(canvas, doc):  # noqa: ANN001
        canvas.saveState()
        canvas.setFont("Helvetica", 8)
        canvas.setFillColor(HexColor("#666666"))
        canvas.drawString(2 * cm, 1.2 * cm, f"Manual de instalação • RespirAR Amazonas v{ver}")
        canvas.drawRightString(A4[0] - 2 * cm, 1.2 * cm, f"Página {doc.page}")
        canvas.setStrokeColor(HexColor("#BBBBBB"))
        canvas.line(2 * cm, 1.6 * cm, A4[0] - 2 * cm, 1.6 * cm)
        canvas.restoreState()

    def imagem(nome: str, altura_cm: float):
        w, hh = PILImage.open(IMG / nome).size
        alt = altura_cm * cm
        return Image(str(IMG / nome), width=alt * w / hh, height=alt)

    saida.parent.mkdir(parents=True, exist_ok=True)
    doc = BaseDocTemplate(
        str(saida), pagesize=A4, leftMargin=2 * cm, rightMargin=2 * cm, topMargin=1.8 * cm, bottomMargin=2.2 * cm,
        title=f"Manual de instalação — RespirAR Amazonas v{ver}", author=" e ".join(AUTORES),
        subject="Download e instalação do aplicativo para Android",
    )
    doc.addPageTemplates([PageTemplate(id="p", frames=[Frame(doc.leftMargin, doc.bottomMargin, doc.width, doc.height, id="f")], onPage=rodape)])

    el: list = []
    # Capa: nome do app + tela de abertura (splash)
    el += [Paragraph("RESPIRAR AMAZONAS", t1), Paragraph("Manual ilustrado de download e instalação para Android", t2),
           imagem("splash.png", 12.6), Spacer(1, 6),
           Paragraph("Tela de abertura do aplicativo (captura da versão 1.13.6; o número de versão exibido acompanha o app instalado)", nota), Spacer(1, 8),
           Paragraph("<b>Autores</b>", cen)]
    el += [Paragraph(a, cen) for a in AUTORES]
    el += [Paragraph("Estudantes de Farmácia — Universidade Federal do Amazonas (UFAM)", cen),
           Paragraph(f"<b>Elaborado em:</b> {ELABORADO_EM} &nbsp;•&nbsp; <b>Atualizado em:</b> {ATUALIZADO_EM}", cen),
           Paragraph(f"<b>Versão do aplicativo:</b> {ver} &nbsp;•&nbsp; <b>Arquivo:</b> {apk}", cen),
           Paragraph(f'<b>Download:</b> <link href="{SITE}" color="#0B57D0">{SITE}</link>', cen), PageBreak()]

    for i, (titulo, texto, img, legenda) in enumerate(ETAPAS, 1):
        bloco = [Paragraph(f"Etapa {i} — {titulo}", h), Paragraph(texto.format(site=SITE, apk=apk), corpo), Spacer(1, 4),
                 imagem(img, 17.5 if i == 1 else 17.0)]
        if legenda:
            bloco += [Spacer(1, 3), Paragraph(legenda.format(apk=apk), nota)]
        el += [KeepTogether(bloco), PageBreak()]

    lista = [
        f"O APK <b>{apk}</b> foi baixado desta plataforma ({SITE}).",
        "A instalação foi concluída sem erros.",
        "O ícone do RespirAR Amazonas aparece na lista de aplicativos.",
        "A permissão para instalar apps desconhecidos foi desativada novamente, caso tenha sido ativada temporariamente.",
        "Ao abrir o app, você leu e aceitou o termo de privacidade (LGPD).",
    ]
    el += [Paragraph("Checklist final", h), Paragraph("Antes de usar o aplicativo, confirme:", corpo)]
    el += [Paragraph("[  ] " + x, corpo) for x in lista]
    el += [Spacer(1, 8),
           Paragraph(f"<b>Autores:</b> {AUTORES[0]} e {AUTORES[1]} — estudantes de Farmácia da Universidade Federal do Amazonas (UFAM).", corpo),
           Paragraph(f"<b>Elaborado em:</b> {ELABORADO_EM}. <b>Atualizado em:</b> {ATUALIZADO_EM} (versão {ver}).", corpo),
           Paragraph("<b>Importante:</b> este manual orienta a instalação a partir do APK fornecido por esta plataforma. "
                     "Se o nome do arquivo, o desenvolvedor ou as telas forem diferentes, interrompa a instalação e confirme "
                     "com a equipe responsável pelo RespirAR Amazonas.", corpo),
           Paragraph(f'<link href="{SITE}" color="#0B57D0">Voltar à plataforma ({SITE})</link>', cen)]
    doc.build(el)
    return saida


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--saida", type=Path, default=PADRAO)
    ap.add_argument("--versao", default=None, help="padrão: arquivo VERSION")
    a = ap.parse_args(argv)
    try:
        import reportlab  # noqa: F401
        import PIL  # noqa: F401
    except ImportError:
        print("Instale as dependências: pip install reportlab pillow", file=sys.stderr)
        return 1
    faltam = [n for n in ("splash.png", "passo-site.png", *[e[2] for e in ETAPAS]) if not (IMG / n).is_file()]
    if faltam:
        print("Imagens ausentes em assets/manual/:", ", ".join(faltam), file=sys.stderr)
        return 1
    print("Manual gerado:", gerar(a.saida, a.versao))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
