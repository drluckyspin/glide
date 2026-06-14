#!/usr/bin/env python3
"""Create site/menubar-base.png by removing the menu card from a desktop capture."""
from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
LAYOUT = ROOT / "scripts" / "screenshot-layout.json"
DEFAULT_SOURCE = ROOT / "site/menubar-source.png"


def prepare_menubar_base(source: Path, output: Path) -> None:
    layout = json.loads(LAYOUT.read_text(encoding="utf-8"))
    card = layout["menubar"]["card"]
    x = int(card["x"])
    y = int(card["y"])
    w = int(card["width"])
    h = int(card["height"])

    image = Image.open(source).convert("RGBA")
    wallpaper = image.crop((400, y, image.width, y + h))
    fill = wallpaper.resize((w, h), Image.Resampling.LANCZOS).filter(ImageFilter.GaussianBlur(radius=0.8))
    image.paste(fill, (x, y))
    output.parent.mkdir(parents=True, exist_ok=True)
    image.save(output)
    print(f"Wrote {output}")


def main() -> None:
    source = DEFAULT_SOURCE if DEFAULT_SOURCE.exists() else ROOT / "site/menubar.png"
    if not source.exists():
        raise SystemExit(
            "No menubar source image found. Save a desktop capture as site/menubar-source.png "
            "before regenerating site/menubar-base.png."
        )
    prepare_menubar_base(source, ROOT / "site/menubar-base.png")


if __name__ == "__main__":
    main()
