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

	MENUBAR_OUTPUT="$ROOT/$(read_layout menubar.output)"

	python3 - "$ROOT" "$MENUBAR_OUTPUT" <<'PY'
import sys
from pathlib import Path

root = Path(sys.argv[1])
output = Path(sys.argv[2])
sys.path.insert(0, str(root / "scripts"))
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader("patch", SourceFileLoader("patch", str(root / "scripts/patch-screenshot-version.py")))
mod = module_from_spec(spec)
spec.loader.exec_module(mod)
# composite_menubar reads the base image from the layout; pass the configured output path.
mod.composite_menubar(root / "site/drop-down.png", output)
PY
else
	echo "Swift screenshot renderer unavailable; using PNG patch fallback." >&2
	echo "----- screenshot renderer build output -----" >&2
	cat /tmp/screenshot-renderer-build.err >&2 2>/dev/null || true
	echo "--------------------------------------------" >&2
	python3 "$ROOT/scripts/patch-screenshot-version.py"
fi

echo "Updated docs/drop-down.png, docs/onboarding.png, site/drop-down.png, site/onboarding.png, site/menubar.png"
