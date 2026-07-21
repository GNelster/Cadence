#!/bin/bash
# Builds Cadence.app from the SwiftPM release binary.
set -euo pipefail

cd "$(dirname "$0")/.."

swift build -c release

APP="build/Cadence.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/Cadence "$APP/Contents/MacOS/Cadence"

# App icon (generated once; rerun scripts/make_icon.swift to change it).
if [ -f "Resources/Cadence.icns" ]; then
    cp Resources/Cadence.icns "$APP/Contents/Resources/Cadence.icns"
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>local.cadence</string>
    <key>CFBundleName</key>
    <string>Cadence</string>
    <key>CFBundleExecutable</key>
    <string>Cadence</string>
    <key>CFBundleIconFile</key>
    <string>Cadence</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
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

# Prefer the stable local identity (keeps macOS permission grants valid
# across rebuilds); fall back to ad-hoc.
if security find-identity -v -p codesigning 2>/dev/null | grep -q "WhisperFlow Dev"; then
    codesign --force --sign "WhisperFlow Dev" "$APP"
    echo "Signed with 'WhisperFlow Dev'."
else
    codesign --force --sign - "$APP"
    echo "Signed ad-hoc (run scripts/make_signing_cert.sh for a stable identity)."
fi

echo "Built $APP"
