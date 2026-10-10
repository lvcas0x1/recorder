#!/bin/zsh
# Package build/Recorder.app into build/Recorder-<version>.dmg with an Applications link,
# using `diskutil image`.
# Usage: Scripts/make-dmg.sh <version>
set -euo pipefail
cd "$(dirname "$0")/.."

version=${1:?usage: make-dmg.sh <version>}
app=build/Recorder.app
dmg="build/Recorder-$version.dmg"
[[ -d "$app" ]] || { echo "missing $app: run Scripts/build-app.sh first"; exit 1; }

staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"
rm -f "$dmg"
# diskutil image replaces hdiutil, which is deprecated as of macOS 27. A folder source becomes an
# APFS volume; ULFO is a compressed read-only image.
diskutil image create from --format ULFO --volumeName "Recorder" "$staging" "$dmg" >/dev/null
echo "$dmg"
