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

composite_menubar() {
	# Stamp the freshly rendered dropdown onto the clean menubar capture (Pillow).
	local output
	output="$ROOT/$(read_layout menubar.output)"
	python3 - "$ROOT" "$output" <<'PY'
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
}

# Fail fast when rendered PNG dimensions drift from scripts/screenshot-layout.json.
# If OnboardingView or StatusMenuView layout changes, update the layout file and the
# matching aspect-ratio rules in site/index.html (see siteCss hints in the layout).
verify_screenshot_sizes() {
	python3 - "$ROOT" "$LAYOUT" <<'PY'
import json
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print(
        "warning: Pillow not installed; skipping screenshot dimension verification",
        file=sys.stderr,
    )
    raise SystemExit(0)

root = Path(sys.argv[1])
layout = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
errors: list[str] = []

for key in ("dropdown", "onboarding", "menubar"):
    entry = layout[key]
    width = int(entry["width"])
    height = int(entry["height"])
    paths = {entry.get("docs"), entry.get("site"), entry.get("output")}
    paths = sorted({p for p in paths if p})
    for rel in paths:
        path = root / rel
        if not path.exists():
            errors.append(f"{key}: missing {rel}")
            continue
        with Image.open(path) as img:
            actual_w, actual_h = img.size
        if actual_w != width or actual_h != height:
            hint = entry.get("siteCss", "site/index.html aspect-ratio")
            errors.append(
                f"{key}: {rel} is {actual_w}x{actual_h}, expected {width}x{height} "
                f"(update scripts/screenshot-layout.json and {hint})"
            )

if errors:
    print("error: screenshot dimension drift detected:", file=sys.stderr)
    for line in errors:
        print(f"  - {line}", file=sys.stderr)
    raise SystemExit(1)
PY
}

VERSION="$(tr -d ' \n\r' < "$ROOT/VERSION")"
VERSION="${VERSION#v}"

# Render the real app views (macOS only). Build the actual app with xcodebuild so the
# asset catalog, fonts, and full view layer match production exactly, then run it in
# the hidden `--screenshot` mode. Falls back to the Linux PNG patch when unavailable.
APP_BUILD_DIR="$ROOT/build/screenshots"
BUILD_LOG=/tmp/glide-screenshot-build.log

if command -v xcodebuild >/dev/null 2>&1 && xcodebuild build \
	-project "$ROOT/Glide.xcodeproj" \
	-scheme Glide \
	-configuration Release \
	-derivedDataPath "$APP_BUILD_DIR" \
	-destination 'platform=macOS' \
	CODE_SIGNING_ALLOWED=NO \
	>"$BUILD_LOG" 2>&1; then

	APP_BIN="$APP_BUILD_DIR/Build/Products/Release/Glide.app/Contents/MacOS/Glide"
	if [[ ! -x "$APP_BIN" ]]; then
		APP_BIN="$(find "$APP_BUILD_DIR/Build/Products" -name Glide -type f -perm -111 2>/dev/null | head -n 1)"
	fi

	if [[ -z "$APP_BIN" || ! -x "$APP_BIN" ]]; then
		echo "error: xcodebuild succeeded but the Glide binary was not found under" >&2
		echo "       $APP_BUILD_DIR/Build/Products (build output layout may have changed)." >&2
		exit 1
	fi

	echo "Rendering screenshots from $APP_BIN (v$VERSION)"
	"$APP_BIN" --screenshot \
		--menu "$ROOT/docs/drop-down.png" \
		--onboarding "$ROOT/docs/onboarding.png" \
		--version "$VERSION"

	cp "$ROOT/docs/drop-down.png" "$ROOT/site/drop-down.png"
	cp "$ROOT/docs/onboarding.png" "$ROOT/site/onboarding.png"
	composite_menubar
else
	echo "xcodebuild app render unavailable; using PNG patch fallback." >&2
	echo "----- app build output (tail) -----" >&2
	tail -n 60 "$BUILD_LOG" >&2 2>/dev/null || true
	echo "-----------------------------------" >&2
	python3 "$ROOT/scripts/patch-screenshot-version.py"
fi

verify_screenshot_sizes

echo "Updated docs/drop-down.png, docs/onboarding.png, site/drop-down.png, site/onboarding.png, site/menubar.png"
