#!/usr/bin/env bash
# Regenerate docs/ and site/ screenshots that embed the app version.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RENDERER="$("$ROOT/scripts/build-screenshot-renderer.sh")"
LAYOUT="$ROOT/scripts/screenshot-layout.json"

if [[ ! -f "$ROOT/VERSION" ]]; then
	echo "VERSION file not found. Run make bump-version first." >&2
	exit 1
fi

if [[ ! -f "$LAYOUT" ]]; then
	echo "Layout file not found: $LAYOUT" >&2
	exit 1
fi

VERSION="$(tr -d ' \n\r' < "$ROOT/VERSION")"
VERSION="${VERSION#v}"

read_layout() {
	python3 - "$LAYOUT" "$1" <<'PY'
import json, sys
path, key = sys.argv[1], sys.argv[2]
with open(path) as f:
    data = json.load(f)
cur = data
for part in key.split("."):
    cur = cur[part]
print(cur)
PY
}

MENUBAR_BASE="$ROOT/$(read_layout menubar.base)"
MENUBAR_OUTPUT="$ROOT/$(read_layout menubar.output)"
MENUBAR_X="$(read_layout menubar.dropdown.x)"
MENUBAR_Y="$(read_layout menubar.dropdown.y)"

if [[ ! -f "$MENUBAR_BASE" ]]; then
	echo "Menubar base image not found: $MENUBAR_BASE" >&2
	exit 1
fi

cd "$ROOT"

"$RENDERER" --version "$VERSION" docs/drop-down.png menu
cp docs/drop-down.png site/drop-down.png

"$RENDERER" docs/onboarding.png onboarding
cp docs/onboarding.png site/onboarding.png

"$RENDERER" composite "$MENUBAR_BASE" site/drop-down.png "$MENUBAR_X" "$MENUBAR_Y" "$MENUBAR_OUTPUT"

echo "Updated docs/drop-down.png, docs/onboarding.png, site/drop-down.png, site/onboarding.png, site/menubar.png (v$VERSION)"
echo "Note: site/glide-hero.png is still a full-desktop capture — update manually if needed."
