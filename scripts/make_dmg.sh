#!/bin/bash
# Builds Cadence.app (via make_app.sh) and packages it into a DMG for
# distribution. If make_app.sh signed with a real Developer ID Application
# cert and a "cadence-notary" keychain profile exists (set up once via
# `xcrun notarytool store-credentials cadence-notary`), this also notarizes
# and staples the DMG. Otherwise it's an unnotarized build — see README for
# first-launch instructions.
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:-1.1}"
BUILD="${2:-2}"
APP="build/Cadence.app"
DMG="build/Cadence-$VERSION.dmg"
NOTARY_PROFILE="cadence-notary"

./scripts/make_app.sh "$VERSION" "$BUILD"

rm -rf build/dmg-staging "$DMG"
mkdir -p build/dmg-staging
cp -R "$APP" build/dmg-staging/
ln -s /Applications build/dmg-staging/Applications

hdiutil create -volname "Cadence" -srcfolder build/dmg-staging \
    -ov -format UDZO "$DMG"

rm -rf build/dmg-staging

echo "Built $DMG"

IS_DEV_ID_SIGNED=$(codesign -dv "$APP" 2>&1 | grep -q "Developer ID Application" && echo 1 || echo 0)
if [ "$IS_DEV_ID_SIGNED" = "1" ] && xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "Notarizing (this can take a few minutes)…"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    echo "Notarized and stapled $DMG."
elif [ "$IS_DEV_ID_SIGNED" = "1" ]; then
    echo "Signed with a Developer ID cert but no '$NOTARY_PROFILE' keychain profile found."
    echo "Run once: xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <id> --team-id XX45YMU835 --password <app-specific-password>"
else
    echo "Not signed with a Developer ID cert — skipping notarization. Users will need to right-click ▸ Open on first launch."
fi
