#!/usr/bin/env python3
"""Patch vX.Y.Z label in menu dropdown PNGs (Linux fallback when make screenshots is unavailable)."""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
LAYOUT = ROOT / "scripts" / "screenshot-layout.json"
VERSION_RE = re.compile(r"v\d+\.\d+\.\d+")


def read_version() -> str:
    raw = (ROOT / "VERSION").read_text(encoding="utf-8").strip().lstrip("v")
    if not raw:
        raise SystemExit("VERSION file is empty")
    return raw


def load_font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = [
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
    ]
    for path in candidates:
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def version_bbox(img: Image.Image) -> tuple[int, int, int, int]:
    data = img.load()
    width, height = img.size
    pixels: list[tuple[int, int]] = []

    for y in range(24, min(36, height)):
        for x in range(44, min(100, width)):
            r, g, b, a = data[x, y]
            if a < 200:
                continue
            if 95 <= r <= 185 and abs(int(r) - int(g)) < 22 and abs(int(g) - int(b)) < 22:
                pixels.append((x, y))

    if not pixels:
        raise RuntimeError("Could not locate version label in dropdown image")

    xs = [p[0] for p in pixels]
    ys = [p[1] for p in pixels]
    return min(xs) - 1, min(ys) - 1, max(xs) + 2, max(ys) + 2


def patch_dropdown(path: Path, version: str) -> None:
    img = Image.open(path).convert("RGBA")
    draw = ImageDraw.Draw(img)
    x0, y0, x1, y1 = version_bbox(img)
    sample_x = max(0, x0 - 2)
    sample_y = min(img.height - 1, y0 + 2)
    bg = img.getpixel((sample_x, sample_y))[:3]
    draw.rectangle([x0, y0, x1, y1], fill=bg + (255,))

    font = load_font(10)
    text = f"v{version}"
    text_color = (255, 255, 255, int(255 * 0.55))
    ascent, _ = font.getmetrics()
    text_y = y0 + max(0, (y1 - y0 - ascent) // 2) - 1
    draw.text((x0, text_y), text, fill=text_color, font=font)
    img.save(path)
    print(f"Patched {path} -> {text}")


def composite_menubar(dropdown: Path, output: Path) -> None:
    layout = json.loads(LAYOUT.read_text(encoding="utf-8"))
    menubar = layout["menubar"]
    base = ROOT / menubar["base"]
    x = int(menubar["dropdown"]["x"])
    y = int(menubar["dropdown"]["y"])
    overlay = Image.open(dropdown).convert("RGBA")
    canvas = Image.open(base).convert("RGBA")

    # Opaque backing so any transparency in the PNG does not reveal the old menu in base.
    card_color = overlay.getpixel((8, 32))[:3]
    backing = Image.new("RGBA", overlay.size, card_color + (255,))
    canvas.paste(backing, (x, y))
    canvas.paste(overlay, (x, y), overlay)
    canvas.save(output)
    print(f"Composited {output}")


def main() -> None:
    version = read_version()
    dropdown_paths = [ROOT / "docs/drop-down.png", ROOT / "site/drop-down.png"]
    for path in dropdown_paths:
        if not path.exists():
            raise SystemExit(f"Missing {path}")
        patch_dropdown(path, version)

    composite_menubar(ROOT / "site/drop-down.png", ROOT / "site/menubar.png")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # noqa: BLE001
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1) from exc
