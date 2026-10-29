#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
APP="$PWD/Token额度.app"
VERSION=$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$APP/Contents/Info.plist")
mkdir -p dist
ASSET="TokenQuotaMac-v${VERSION}-arm64.zip"
codesign --verify --deep --strict "$APP"
ditto -c -k --norsrc --noextattr --keepParent "$APP" "dist/$ASSET"
(cd dist && shasum -a 256 "$ASSET" > SHA256SUMS.txt)
echo "已生成 dist/$ASSET 与 SHA256SUMS.txt"
