#!/usr/bin/env python3
"""Patch vX.Y.Z label in menu dropdown PNGs (Linux fallback when make screenshots is unavailable)."""
from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

# Pillow >= 9.1 exposes resampling filters under Image.Resampling; older releases
# only have the top-level constants (e.g. Image.LANCZOS).
try:
    LANCZOS = Image.Resampling.LANCZOS
except AttributeError:  # pragma: no cover - Pillow < 9.1
    LANCZOS = Image.LANCZOS

ROOT = Path(__file__).resolve().parents[1]
LAYOUT = ROOT / "scripts" / "screenshot-layout.json"


def read_version() -> str:
    raw = (ROOT / "VERSION").read_text(encoding="utf-8").strip().lstrip("v")
    if not raw:
        raise SystemExit("VERSION file is empty")
    return raw


def load_font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    # Prefer the macOS system font (so a patch on macOS matches SwiftUI exactly);
    # on Linux fall back to Liberation Sans, which is metric-compatible with the
    # Helvetica/Arial-style UI font and lines up far better than DejaVu Sans.
    candidates = [
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    ]
    for path in candidates:
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def title_metrics(img: Image.Image) -> tuple[int, int, int]:
    """Locate the white 'Glide' title: returns (right_x, baseline_y, top_y).

    The version label is rendered immediately to its right, sharing the baseline.
    Only the title is white near the top-left; the version is muted grey and the
    expand icon sits far right, so a brightness scan limited to the left columns
    isolates 'Glide' reliably regardless of the version string.
    """
    data = img.load()
    right = top = bottom = None
    for y in range(12, 52):
        for x in range(10, 110):
            r, g, b, a = data[x, y]
            if a >= 180 and r > 200 and g > 200 and b > 200:
                right = x if right is None else max(right, x)
                bottom = y if bottom is None else max(bottom, y)
                top = y if top is None else min(top, y)
    if right is None:
        raise RuntimeError("Could not locate 'Glide' title in dropdown image")
    return right, bottom, top


def patch_dropdown(path: Path, version: str) -> None:
    img = Image.open(path).convert("RGBA")
    draw = ImageDraw.Draw(img)
    glide_right, baseline, top = title_metrics(img)

    # Sample the card background from an empty patch on the title line, between the
    # version label and the expand icon, so the erase fill matches exactly.
    bg = img.getpixel((min(img.width - 1, glide_right + 90), baseline - 3))[:3]
    draw.rectangle([glide_right + 3, top - 4, glide_right + 88, baseline + 4], fill=bg + (255,))

    font = load_font(10)
    text = f"v{version}"
    text_color = (255, 255, 255, int(255 * 0.6))
    # anchor="ls" places the text by its left edge and baseline, so the version
    # sits on the same baseline as 'Glide' (matching the SwiftUI layout).
    draw.text((glide_right + 7, baseline), text, fill=text_color, font=font, anchor="ls")
    img.save(path)
    print(f"Patched {path} -> {text}")


def composite_menubar(dropdown: Path, output: Path) -> None:
    layout = json.loads(LAYOUT.read_text(encoding="utf-8"))
    menubar = layout["menubar"]
    base = ROOT / menubar["base"]
    card = menubar["card"]
    card_x = int(card["x"])
    card_y = int(card["y"])
    card_w = int(card["width"])
    card_h = int(card["height"])

    overlay = Image.open(dropdown).convert("RGBA")
    canvas = Image.open(base).convert("RGBA")

    # The base is a clean menubar capture whose card silhouette, rounded corners,
    # drop shadow, and surrounding wallpaper are all pixel-perfect. The menu card
    # is always the same rounded rectangle regardless of its contents, so we simply
    # scale the freshly rendered dropdown to that footprint and stamp it over the
    # old card. The new card fully covers the old body; its anti-aliased corners
    # reveal the original wallpaper + contact shadow underneath, so corners and
    # shadow match the source exactly (no synthesized shadow or wallpaper fill,
    # which is what previously produced bright fringes at the corners).
    scaled = overlay.resize((card_w, card_h), LANCZOS)
    canvas.paste(scaled, (card_x, card_y), scaled)
    canvas.save(output)
    print(f"Composited {output} (card {card_w}x{card_h} at {card_x},{card_y})")


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
