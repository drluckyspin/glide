#!/usr/bin/env bash
# Build screenshot-renderer.app — a minimal .app bundle so SwiftUI asset catalog images resolve.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/screenshot-renderer.app"
BIN="$APP/Contents/MacOS/ScreenshotRenderer"
RES="$APP/Contents/Resources"
PARTIAL_PLIST="$ROOT/build/screenshot-renderer-partial.plist"
SDK="$(xcrun --show-sdk-path)"
ARCH="$(uname -m)"
TARGET="${ARCH}-apple-macos13.0"

mkdir -p "$APP/Contents/MacOS" "$RES"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>ScreenshotRenderer</string>
	<key>CFBundleIdentifier</key>
	<string>io.github.drluckyspin.glide.screenshot-renderer</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>ScreenshotRenderer</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>LSUIElement</key>
	<true/>
</dict>
</plist>
PLIST

xcrun actool "$ROOT/Glide/Images.xcassets" \
	--compile "$RES" \
	--platform macosx \
	--minimum-deployment-target 13.0 \
	--output-partial-info-plist "$PARTIAL_PLIST"

swiftc -O \
	-sdk "$SDK" \
	-target "$TARGET" \
	-o "$BIN" \
	"$ROOT/scripts/ScreenshotRenderer/main.swift" \
	"$ROOT/Glide/StatusMenuView.swift" \
	"$ROOT/Glide/Preferences.swift" \
	"$ROOT/Glide/OnboardingView.swift" \
	-framework AppKit \
	-framework SwiftUI \
	-framework CoreGraphics \
	-framework ImageIO

echo "$BIN"
