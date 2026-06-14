#!/usr/bin/env bash
# Regenerate docs/ and site/ screenshots that embed the app version.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LAYOUT="$ROOT/scripts/screenshot-layout.json"

if [[ ! -f "$ROOT/VERSION" ]]; then
	echo "VERSION file not found. Run make bump-version first." >&2
	exit 1
fi

if [[ ! -f "$LAYOUT" ]]; then
	echo "Layout file not found: $LAYOUT" >&2
	exit 1
fi

cd "$ROOT"

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

if bash "$ROOT/scripts/build-screenshot-renderer.sh" >/tmp/screenshot-renderer-path.txt 2>/tmp/screenshot-renderer-build.err; then
	RENDERER="$(cat /tmp/screenshot-renderer-path.txt)"
	VERSION="$(tr -d ' \n\r' < "$ROOT/VERSION")"
	VERSION="${VERSION#v}"

	"$RENDERER" --version "$VERSION" docs/drop-down.png menu
	cp docs/drop-down.png site/drop-down.png

	"$RENDERER" docs/onboarding.png onboarding
	cp docs/onboarding.png site/onboarding.png

	MENUBAR_BASE="$ROOT/$(read_layout menubar.base)"
	MENUBAR_OUTPUT="$ROOT/$(read_layout menubar.output)"
	MENUBAR_X="$(read_layout menubar.dropdown.x)"
	MENUBAR_Y="$(read_layout menubar.dropdown.y)"

	"$RENDERER" composite "$MENUBAR_BASE" site/drop-down.png "$MENUBAR_X" "$MENUBAR_Y" "$MENUBAR_OUTPUT"
else
	echo "Swift screenshot renderer unavailable; using PNG patch fallback." >&2
	python3 "$ROOT/scripts/patch-screenshot-version.py"
fi

echo "Updated docs/drop-down.png, docs/onboarding.png, site/drop-down.png, site/onboarding.png, site/menubar.png"
