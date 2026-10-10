#!/bin/zsh
# Builds Recorder with SwiftPM and assembles build/Recorder.app (signed with a stable identity when available).
# Optional environment: APP_VERSION (CFBundleShortVersionString), BUILD_NUMBER (CFBundleVersion), SIGN_IDENTITY.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

CONFIG="${1:-release}"
swift build -c "$CONFIG" --product Recorder
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Recorder"

APP="build/Recorder.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/Recorder"
cp Scripts/Info.plist "$APP/Contents/Info.plist"
[[ -n "${APP_VERSION:-}" ]] && plutil -replace CFBundleShortVersionString -string "$APP_VERSION" "$APP/Contents/Info.plist"
[[ -n "${BUILD_NUMBER:-}" ]] && plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP/Contents/Info.plist"
# A stable identity keeps the Screen Recording permission across rebuilds; ad-hoc signing changes it every build.
IDENTITY="${SIGN_IDENTITY:-Screenshot Dev}"
if security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
    codesign --force --sign "$IDENTITY" --identifier dev.lvcas0x1.recorder "$APP"
else
    echo "warning: identity '$IDENTITY' not found; using ad-hoc signing (permission resets on every build)"
    codesign --force --sign - --identifier dev.lvcas0x1.recorder "$APP"
fi
echo "Built $APP"
