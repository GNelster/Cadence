#!/bin/bash
# Builds Cadence.app from the SwiftPM release binary.
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:-1.1}"
BUILD="${2:-2}"

# Garrett's paid Apple Developer Program team (from Xcode's
# IDEProvisioningTeamByIdentifier prefs) — used so a "Developer ID
# Application" cert, once created for this team via Xcode ▸ Settings ▸
# Accounts ▸ Manage Certificates, signs with the right team ID.
DEVELOPMENT_TEAM="XX45YMU835"

swift build -c release

APP="build/Cadence.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/Cadence "$APP/Contents/MacOS/Cadence"

# App icon (generated once; rerun scripts/make_icon.swift to change it).
if [ -f "Resources/Cadence.icns" ]; then
    cp Resources/Cadence.icns "$APP/Contents/Resources/Cadence.icns"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.gnelster.cadence</string>
    <key>CFBundleName</key>
    <string>Cadence</string>
    <key>CFBundleExecutable</key>
    <string>Cadence</string>
    <key>CFBundleIconFile</key>
    <string>Cadence</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Cadence records your voice while you hold the dictation key so it can transcribe it on-device.</string>
    <key>NSHumanReadableCopyright</key>
    <string>Local build — no data leaves this Mac.</string>
</dict>
</plist>
PLIST

# Prefer a real "Developer ID Application" cert for this team (needed for
# notarized, Gatekeeper-clean distribution outside the App Store). Fall
# back to the stable local self-signed identity (keeps macOS permission
# grants valid across rebuilds), then to plain ad-hoc.
DEV_ID_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
    | grep "Developer ID Application: .*($DEVELOPMENT_TEAM)" \
    | head -1 | sed -E 's/^[[:space:]]*[0-9]+\) [0-9A-F]+ "(.+)"$/\1/' || true)

if [ -n "$DEV_ID_IDENTITY" ]; then
    codesign --force --options runtime --timestamp \
        --sign "$DEV_ID_IDENTITY" "$APP"
    echo "Signed with '$DEV_ID_IDENTITY' (team $DEVELOPMENT_TEAM, hardened runtime) — ready to notarize."
elif security find-identity -v -p codesigning 2>/dev/null | grep -q "WhisperFlow Dev"; then
    codesign --force --sign "WhisperFlow Dev" "$APP"
    echo "Signed with 'WhisperFlow Dev' (local only, not notarizable)."
    echo "For a distributable build: Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates ▸ + ▸ Developer ID Application, under team $DEVELOPMENT_TEAM."
else
    codesign --force --sign - "$APP"
    echo "Signed ad-hoc (run scripts/make_signing_cert.sh for a stable identity)."
fi

echo "Built $APP ($VERSION build $BUILD)"
