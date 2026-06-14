#!/usr/bin/env python3
"""Create site/menubar-base.png by removing the menu card from a desktop capture."""
from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
LAYOUT = ROOT / "scripts" / "screenshot-layout.json"
DEFAULT_SOURCE = ROOT / "site/menubar-source.png"


def prepare_menubar_base(source: Path, output: Path) -> None:
    layout = json.loads(LAYOUT.read_text(encoding="utf-8"))
    menubar = layout["menubar"]
    clear = menubar.get("clear", menubar["card"])
    x = int(clear["x"])
    y = int(clear["y"])
    w = int(clear["width"])
    h = int(clear["height"])

    feather = int(clear.get("feather", 28))

    image = Image.open(source).convert("RGBA")

    # Sample clean wallpaper from the right side of the capture (no menu card there)
    # and stretch it over the entire old card + shadow footprint so nothing of the
    # previous menu (border, body, or drop shadow) survives in the base.
    sample_left = min(image.width - 1, x + w + 2)
    wallpaper = image.crop((sample_left, y, image.width, y + h))
    fill = wallpaper.resize((w, h), Image.Resampling.LANCZOS).filter(ImageFilter.GaussianBlur(radius=0.8))

    # Feather the fill into the surrounding wallpaper. The diagonal gradient means a
    # right-side sample never matches the left edge exactly, so a hard paste leaves a
    # visible rectangular seam. A blurred mask blends the edges smoothly; the centre
    # (which the menu card covers) stays fully opaque.
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rectangle([feather, feather, w - feather, h - feather], fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(radius=feather / 2))
    image.paste(fill, (x, y), mask)
    output.parent.mkdir(parents=True, exist_ok=True)
    image.save(output)
    print(f"Wrote {output} (cleared {w}x{h} at {x},{y}, feather {feather})")


def main() -> None:
    layout = json.loads(LAYOUT.read_text(encoding="utf-8"))
    menubar = layout["menubar"]
    configured = menubar.get("source")
    candidates = [
        ROOT / configured if configured else None,
        DEFAULT_SOURCE,
        ROOT / "site/menubar.png",
    ]
    source = next((c for c in candidates if c and c.exists()), None)
    if source is None:
        raise SystemExit(
            "No menubar source image found. Save a clean desktop capture (menu bar + "
            "wallpaper, with a menu card whose right side is clear wallpaper) as "
            "site/menubar-source.png before regenerating site/menubar-base.png."
        )
    prepare_menubar_base(source, ROOT / menubar["base"])


if __name__ == "__main__":
    main()
