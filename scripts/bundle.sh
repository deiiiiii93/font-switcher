#!/usr/bin/env bash
# Builds build/FontSwitcher.app (release, ad-hoc signed, unsandboxed).
# Usage: scripts/bundle.sh            then: open build/FontSwitcher.app
#        cp -R build/FontSwitcher.app /Applications/   to install
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# SwiftBuild currently links SwiftPM apps with the deployment target as the SDK version,
# which opts out of the modern macOS window and toolbar appearance. The native build
# system records the actual SDK version while retaining the macOS 15 deployment target.
swift build --build-system native -c release --product FontSwitcher
BIN_DIR="$(swift build --build-system native -c release --show-bin-path)"

APP="$ROOT/build/FontSwitcher.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/FontSwitcher" "$APP/Contents/MacOS/FontSwitcher"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns Resources/MenuBarIcon.png Resources/MenuBarIcon@2x.png "$APP/Contents/Resources/"

codesign --force --sign - "$APP"
echo "$APP"
