#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
TOKEN_ICON_WORK=$(mktemp -d "${TMPDIR:-/tmp}/token-icon.XXXXXX")
trap 'rm -rf "$TOKEN_ICON_WORK"' EXIT
cp Tools/GenerateIcon.swift "$TOKEN_ICON_WORK/main.swift"
xcrun swiftc -swift-version 5 Sources/TokenGlyph.swift "$TOKEN_ICON_WORK/main.swift" -o "$TOKEN_ICON_WORK/render"
"$TOKEN_ICON_WORK/render" "$TOKEN_ICON_WORK/TokenBadge.iconset"
iconutil -c icns -o Badge.icns "$TOKEN_ICON_WORK/TokenBadge.iconset"
