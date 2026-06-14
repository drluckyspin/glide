#!/usr/bin/env bash
# Regenerate docs/ and site/ screenshots that embed the app version.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RENDERER="$("$ROOT/scripts/build-screenshot-renderer.sh")"

if [[ ! -f "$ROOT/VERSION" ]]; then
	echo "VERSION file not found. Run make bump-version first." >&2
	exit 1
fi

VERSION="$(tr -d ' \n\r' < "$ROOT/VERSION")"
VERSION="${VERSION#v}"

cd "$ROOT"

"$RENDERER" --version "$VERSION" docs/drop-down.png menu
cp docs/drop-down.png site/drop-down.png

"$RENDERER" docs/onboarding.png onboarding
cp docs/onboarding.png site/onboarding.png

echo "Updated docs/drop-down.png, docs/onboarding.png, site/drop-down.png, site/onboarding.png (v$VERSION)"
echo "Note: site/menubar.png and glide-hero.png are full-desktop captures — update those manually if needed."
