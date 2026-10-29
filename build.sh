#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
APP="$PWD/Token额度.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "${TMPDIR:-/tmp}/codex-badge-mac-swift-cache"
xcrun swiftc -swift-version 5 -target arm64-apple-macosx13.0 -O -module-cache-path "${TMPDIR:-/tmp}/codex-badge-mac-swift-cache" \
    -framework Cocoa -framework SwiftUI -framework ServiceManagement \
    Sources/Quota.swift Sources/DisplayFormat.swift Sources/TokenGlyph.swift Sources/App.swift Tests/QuotaTests.swift Sources/main.swift \
    -o "$APP/Contents/MacOS/CodexBadge"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>CodexBadge</string>
<key>CFBundleIdentifier</key><string>local.henry.CodexBadge</string>
<key>CFBundleName</key><string>Token额度</string>
<key>CFBundleDisplayName</key><string>Token额度</string>
<key>CFBundleIconFile</key><string>Badge</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.5.2</string>
<key>CFBundleVersion</key><string>8</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>Native Mac implementation. Inspired by returnk/codex-usage-badge (MIT).</string>
</dict></plist>
PLIST
cp THIRD_PARTY_LICENSE.txt "$APP/Contents/Resources/THIRD_PARTY_LICENSE.txt"
if [[ -f LICENSE ]]; then cp LICENSE "$APP/Contents/Resources/LICENSE"; fi
if [[ -f Badge.icns ]]; then cp Badge.icns "$APP/Contents/Resources/Badge.icns"; fi
codesign --force --sign - "$APP"
"$APP/Contents/MacOS/CodexBadge" --self-test
