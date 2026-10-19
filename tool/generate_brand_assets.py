#!/usr/bin/env python3
"""Gera os ativos de marca do app a partir do logo oficial da UFAM.

Uso:
    python3 tool/generate_brand_assets.py caminho/para/logo_ufam.png

Saídas (dentro do projeto):
    assets/images/ufam_logo.png        logo da UFAM, reduzido (mantém transparência)
    assets/icon/app_icon.png           ícone 1024x1024 sem transparência (iOS exige)
    assets/icon/app_icon_foreground.png  marca branca para ícone adaptativo e splash

Dependências: Pillow (pip install pillow).
Os ativos são determinísticos: rodar o script de novo gera arquivos idênticos.
"""
import math
import shutil
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
GREEN_TOP = (27, 94, 32)     # #1B5E20
GREEN_BOTTOM = (67, 160, 71)  # #43A047
WHITE = (255, 255, 255)
SIZE = 1024


def gradient_background(size: int) -> Image.Image:
    img = Image.new("RGB", (size, size), GREEN_TOP)
    draw = ImageDraw.Draw(img)
    for y in range(size):
        t = y / (size - 1)
        color = tuple(round(GREEN_TOP[i] + (GREEN_BOTTOM[i] - GREEN_TOP[i]) * t) for i in range(3))
        draw.line([(0, y), (size, y)], fill=color)
    return img


def draw_wave(draw: ImageDraw.ImageDraw, cx: float, cy: float, half_width: float,
              amplitude: float, thickness: int, color, phase: float = 0.0) -> None:
    """Desenha uma faixa senoidal com pontas arredondadas (representa a fumaça/ar).

    A faixa é preenchida como polígono (topo + base invertida), o que evita
    as falhas que o traço espesso do Pillow produz em polilinhas longas.
    """
    steps = 400
    center_line = []
    for i in range(steps + 1):
        x = cx - half_width + (2 * half_width) * i / steps
        y = cy + amplitude * math.sin(2 * math.pi * (x - cx) / (2 * half_width) * 1.5 + phase)
        center_line.append((x, y))

    r = thickness / 2
    top, bottom = [], []
    for i, (x, y) in enumerate(center_line):
        j0, j1 = max(i - 1, 0), min(i + 1, steps)
        dx = center_line[j1][0] - center_line[j0][0]
        dy = center_line[j1][1] - center_line[j0][1]
        length = math.hypot(dx, dy) or 1.0
        nx, ny = -dy / length, dx / length  # normal unitária
        top.append((x + nx * r, y + ny * r))
        bottom.append((x - nx * r, y - ny * r))

    draw.polygon(top + bottom[::-1], fill=color)
    for x, y in (center_line[0], center_line[-1]):
        draw.ellipse([x - r, y - r, x + r, y + r], fill=color)


def draw_mark(draw: ImageDraw.ImageDraw, size: int, color) -> None:
    cx = cy = size / 2
    thickness = int(size * 0.075)
    half = size * 0.30
    draw_wave(draw, cx, cy - size * 0.17, half, size * 0.035, thickness, color, phase=0.0)
    draw_wave(draw, cx, cy, half, size * 0.035, thickness, color, phase=math.pi / 2)
    draw_wave(draw, cx, cy + size * 0.17, half, size * 0.035, thickness, color, phase=math.pi)


def make_ufam_logo(source: Path, target: Path, max_width: int = 800) -> None:
    img = Image.open(source).convert("RGBA")
    bbox = img.getbbox()  # remove margens transparentes
    if bbox:
        img = img.crop(bbox)
    ratio = max_width / img.width
    if ratio < 1:
        img = img.resize((max_width, round(img.height * ratio)), Image.LANCZOS)
    target.parent.mkdir(parents=True, exist_ok=True)
    img.save(target, optimize=True)


def make_partner_logo(source: Path, target: Path, max_width: int = 512) -> None:
    """Logo de parceiro (CIT-AM), reduzido e salvo em PNG."""
    img = Image.open(source).convert("RGBA")
    ratio = max_width / img.width
    if ratio < 1:
        img = img.resize((max_width, round(img.height * ratio)), Image.LANCZOS)
    target.parent.mkdir(parents=True, exist_ok=True)
    img.save(target, optimize=True)


def main() -> None:
    if len(sys.argv) not in (2, 3):
        sys.exit(__doc__)
    logo_source = Path(sys.argv[1])
    if not logo_source.exists():
        sys.exit(f"Logo não encontrado: {logo_source}")

    make_ufam_logo(logo_source, ROOT / "assets/images/ufam_logo.png")

    if len(sys.argv) == 3:
        cit_source = Path(sys.argv[2])
        if not cit_source.exists():
            sys.exit(f"Logo do CIT não encontrado: {cit_source}")
        make_partner_logo(cit_source, ROOT / "assets/images/cit_am_logo.png")

    icon_dir = ROOT / "assets/icon"
    icon_dir.mkdir(parents=True, exist_ok=True)

    # Renderiza em 2x e reduz com LANCZOS para bordas suavizadas (antialiasing).
    scale = 2
    big = SIZE * scale

    icon = gradient_background(big)
    draw_mark(ImageDraw.Draw(icon), big, WHITE)
    icon = icon.resize((SIZE, SIZE), Image.LANCZOS)
    icon.convert("RGB").save(icon_dir / "app_icon.png", optimize=True)

    foreground = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    draw_mark(ImageDraw.Draw(foreground), big, WHITE + (255,))
    foreground = foreground.resize((SIZE, SIZE), Image.LANCZOS)
    foreground.save(icon_dir / "app_icon_foreground.png", optimize=True)

    print("Ativos gerados em", ROOT / "assets")


if __name__ == "__main__":
    main()
