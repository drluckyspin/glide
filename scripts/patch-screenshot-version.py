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


def _menubar_glyph_runs(base: Image.Image) -> list[tuple[int, int]]:
    """Contiguous x ranges of bright icon/text glyphs in the menu-bar band.

    The bar is translucent over a busy wallpaper, so glyphs are isolated by their
    near-white strokes (max channel) rather than absolute luminance.
    """
    y0, y1 = 42, 61
    runs: list[tuple[int, int]] = []
    start = None
    for x in range(base.width):
        bright = any(max(base.getpixel((x, y))[:3]) > 150 for y in range(y0, y1))
        if bright and start is None:
            start = x
        elif not bright and start is not None:
            if x - 1 - start >= 2:
                runs.append((start, x - 1))
            start = None
    if start is not None and base.width - 1 - start >= 2:
        runs.append((start, base.width - 1))
    return runs


def _status_icon_center_x(base: Image.Image) -> int:
    """Center x of the Glide status icon: first glyph after the largest gap.

    macOS separates the left menu titles (Apple, app menus) from the right status
    items by a wide blank stretch. The Glide icon is the leftmost status item, i.e.
    the first glyph run following that widest gap.
    """
    runs = _menubar_glyph_runs(base)
    if not runs:
        return base.width // 2
    widest_gap = 0
    split_idx = 0
    for i in range(1, len(runs)):
        gap = runs[i][0] - runs[i - 1][1]
        if gap > widest_gap:
            widest_gap = gap
            split_idx = i
    s, e = runs[split_idx]
    return (s + e) // 2


def _menubar_bottom_px(base: Image.Image) -> int:
    """Row of the menu bar's bottom hairline before the desktop wallpaper.

    The bar ends in a bright 1px separator immediately followed by a sharp drop
    into the (darker) wallpaper. Detect that peak across columns that are free of
    glyphs so clock/icon strokes don't confuse the scan.
    """
    cols = list(range(130, 200)) + list(range(410, 445))
    cols = [x for x in cols if 0 <= x < base.width]

    def lum(y: int) -> float:
        return sum(sum(base.getpixel((x, y))[:3]) / 3 for x in cols) / len(cols)

    best_y, best_drop = 31, 0.0
    for y in range(40, base.height - 2):
        drop = lum(y) - lum(y + 1)
        if drop > best_drop:
            best_drop = drop
            best_y = y
    return best_y


def composite_menubar(dropdown: Path, output: Path) -> None:
    layout = json.loads(LAYOUT.read_text(encoding="utf-8"))
    menubar = layout["menubar"]
    base = ROOT / menubar["base"]

    overlay = Image.open(dropdown).convert("RGBA")
    canvas = Image.open(base).convert("RGBA")
    overlay_w, overlay_h = overlay.size

    icon_cx = _status_icon_center_x(canvas)
    card_x = max(4, min(canvas.width - overlay_w - 4, icon_cx - overlay_w // 2))
    menubar_bottom = _menubar_bottom_px(canvas)
    # One pixel below the menu bar, matching AppKit popover placement.
    card_y = menubar_bottom + 1

    # Paste the dropdown at 1× — upscaling blurs the top edge and misaligns the
    # card against the menubar. layout card.* documents the last composite only.
    canvas.paste(overlay, (card_x, card_y), overlay)
    canvas.save(output)
    print(
        f"Composited {output} ({overlay_w}x{overlay_h} at {card_x},{card_y}; "
        f"icon cx={icon_cx}, menubar bottom={menubar_bottom})"
    )


def main() -> None:
    skip_composite = "--skip-composite" in sys.argv
    version = read_version()
    dropdown_paths = [ROOT / "docs/drop-down.png", ROOT / "site/drop-down.png"]
    for path in dropdown_paths:
        if not path.exists():
            raise SystemExit(f"Missing {path}")
        patch_dropdown(path, version)

    if not skip_composite:
        composite_menubar(ROOT / "site/drop-down.png", ROOT / "site/menubar.png")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # noqa: BLE001
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1) from exc
