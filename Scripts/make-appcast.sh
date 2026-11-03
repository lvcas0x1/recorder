#!/bin/zsh
# Writes build/appcast.xml, the Sparkle update feed for one release, with the DMG's EdDSA signature.
# Usage: Scripts/make-appcast.sh <version> <build number> <dmg> <download url>
# Environment: SIGN_UPDATE (path to Sparkle's sign_update). The private key is read from
# SPARKLE_ED_PRIVATE_KEY when set (CI), otherwise from the login keychain (account dev.lvcas0x1.recorder).
set -euo pipefail
cd "$(dirname "$0")/.."

version=${1:?usage: make-appcast.sh <version> <build> <dmg> <url>}
build=${2:?}
dmg=${3:?}
url=${4:?}
sign_update=${SIGN_UPDATE:?set SIGN_UPDATE to the path of Sparkle bin/sign_update}

# Prints: sparkle:edSignature="..." length="..."
if [[ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]]; then
    signature=$(print -rn -- "$SPARKLE_ED_PRIVATE_KEY" | "$sign_update" --ed-key-file - "$dmg")
else
    signature=$("$sign_update" --account dev.lvcas0x1.recorder "$dmg")
fi
minimum=$(plutil -extract LSMinimumSystemVersion raw Scripts/Info.plist)

cat > build/appcast.xml <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Recorder</title>
    <item>
      <title>Recorder $version</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$build</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$minimum</sparkle:minimumSystemVersion>
      <link>https://github.com/lvcas0x1/recorder/releases/tag/v$version</link>
      <enclosure url="$url" type="application/octet-stream" $signature />
    </item>
  </channel>
</rss>
EOF
echo build/appcast.xml
