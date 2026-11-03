#!/bin/zsh
# Builds Recorder with SwiftPM and assembles build/Recorder.app with Sparkle.framework embedded, signed with
# the "Recorder Code Signing" identity when available (the same self-signed identity locally and in CI).
# Optional environment: APP_VERSION (CFBundleShortVersionString), BUILD_NUMBER (CFBundleVersion), SIGN_IDENTITY.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

CONFIG="${1:-release}"
swift build -c "$CONFIG" --product Recorder
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

APP="build/Recorder.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks"
cp "$BIN_DIR/Recorder" "$APP/Contents/MacOS/Recorder"
cp Scripts/Info.plist "$APP/Contents/Info.plist"
[[ -n "${APP_VERSION:-}" ]] && plutil -replace CFBundleShortVersionString -string "$APP_VERSION" "$APP/Contents/Info.plist"
[[ -n "${BUILD_NUMBER:-}" ]] && plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP/Contents/Info.plist"

# Sparkle.framework: ditto keeps the framework's symlinks. The XPC services are only needed by
# sandboxed apps (https://sparkle-project.org/documentation/sandboxing/), so they are removed.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
ditto "$BIN_DIR/Sparkle.framework" "$SPARKLE"
rm -rf "$SPARKLE/Versions/B/XPCServices" "$SPARKLE/XPCServices"
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/Recorder"
# License texts of bundled third-party code (Sparkle is MIT: its notice must ship with the app).
mkdir -p "$APP/Contents/Resources"
ditto Scripts/licenses "$APP/Contents/Resources/licenses"

# A stable identity keeps the Screen Recording permission across updates; ad-hoc signing changes it
# every build. Nested code is signed inside-out, without --deep (Sparkle's sandboxing guide).
IDENTITY="${SIGN_IDENTITY:-Recorder Code Signing}"
if ! security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
    echo "warning: identity '$IDENTITY' not found; using ad-hoc signing (permission resets on every build)"
    IDENTITY="-"
fi
codesign --force --sign "$IDENTITY" "$SPARKLE/Versions/B/Autoupdate"
codesign --force --sign "$IDENTITY" "$SPARKLE/Versions/B/Updater.app"
codesign --force --sign "$IDENTITY" "$SPARKLE"
codesign --force --sign "$IDENTITY" --identifier dev.lvcas0x1.recorder "$APP"
codesign --verify --strict --deep "$APP"
echo "Built $APP"
