#!/usr/bin/env python3
"""Establish site/menubar-base.png — the clean menubar capture used as the
compositing canvas for site/menubar.png.

The menu card is always the same rounded rectangle, so the screenshot pipeline
stamps a freshly rendered dropdown over the card region of this base. That means
the base only needs to be a clean, good-looking menubar screenshot (menu bar +
wallpaper + a menu card at the configured footprint); its surrounding wallpaper,
rounded corners, and drop shadow are reused verbatim. To refresh the desktop or
wallpaper, drop a new capture at site/menubar-source.png and re-run this script.
"""
from __future__ import annotations

import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LAYOUT = ROOT / "scripts" / "screenshot-layout.json"
DEFAULT_SOURCE = ROOT / "site/menubar-source.png"


def main() -> None:
    layout = json.loads(LAYOUT.read_text(encoding="utf-8"))
    base = ROOT / layout["menubar"]["base"]

    if not DEFAULT_SOURCE.exists():
        if base.exists():
            print(f"No {DEFAULT_SOURCE.name}; keeping existing {base}")
            return
        raise SystemExit(
            f"No menubar capture found. Save a clean desktop capture (menu bar + "
            f"wallpaper + a menu card at the configured footprint) as "
            f"{DEFAULT_SOURCE} before regenerating {base}."
        )

    base.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(DEFAULT_SOURCE, base)
    print(f"Wrote {base} from {DEFAULT_SOURCE.name}")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # noqa: BLE001
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1) from exc
