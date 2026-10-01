#!/usr/bin/env python3
"""Genera el icono de LIFEOS para el hub (logo.png) a partir de la marca.

La marca de LifeOS es su acento violeta sobre fondo oscuro. Este script lo
reproduce en el disco redondeado que usa la tarjeta del hub, para que la app no
aparezca con un hueco gris en JUST4ALL.

Uso:
    python3 scripts/make_logo.py <ruta.png> [lado_en_px]

`make_app_icon.sh` lo llama a varios tamaños para construir el `.icns` del
bundle; para el hub basta el de 512.
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw

BRAND = (0x5E, 0x5B, 0xD8)
BRAND_LIGHT = (0x8B, 0x86, 0xF0)
SIDE = 512
RADIUS_RATIO = 0.22


def gradient(size: int) -> Image.Image:
    """Degradado diagonal de marca (arriba-izquierda claro, abajo-derecha base)."""
    image = Image.new("RGB", (size, size))
    pixels = image.load()
    assert pixels is not None
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * (size - 1))
            pixels[x, y] = (
                round(BRAND_LIGHT[0] + (BRAND[0] - BRAND_LIGHT[0]) * t),
                round(BRAND_LIGHT[1] + (BRAND[1] - BRAND_LIGHT[1]) * t),
                round(BRAND_LIGHT[2] + (BRAND[2] - BRAND_LIGHT[2]) * t),
            )
    return image


def target_overlay(size: int) -> Image.Image:
    """Diana blanca: dos anillos y un punto. Es el símbolo de la app."""
    overlay = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    center = size / 2
    white = (255, 255, 255, 255)
    outer = size * 0.30
    middle = size * 0.185
    stroke = max(2, int(size * 0.024))

    draw.ellipse(
        [center - outer, center - outer, center + outer, center + outer],
        outline=white,
        width=stroke,
    )
    draw.ellipse(
        [center - middle, center - middle, center + middle, center + middle],
        outline=(255, 255, 255, 190),
        width=stroke,
    )
    dot = size * 0.062
    draw.ellipse([center - dot, center - dot, center + dot, center + dot], fill=white)
    return overlay


def main() -> int:
    output = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("logo.png")
    side = int(sys.argv[2]) if len(sys.argv) > 2 else SIDE
    radius = int(side * RADIUS_RATIO)

    base = gradient(side).convert("RGBA")

    mask = Image.new("L", (side, side), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, side - 1, side - 1], radius=radius, fill=255)

    icon = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    icon.paste(base, (0, 0), mask)
    icon.alpha_composite(target_overlay(side))

    output.parent.mkdir(parents=True, exist_ok=True)
    icon.save(output, "PNG")
    print(f"Icono escrito en {output} ({side}x{side})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
