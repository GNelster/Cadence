#!/bin/bash
# Builds Cadence.app (via make_app.sh) and packages it into a DMG for
# distribution. Not notarized — see README for first-launch instructions.
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:-1.0}"
APP="build/Cadence.app"
DMG="build/Cadence-$VERSION.dmg"

./scripts/make_app.sh

rm -rf build/dmg-staging "$DMG"
mkdir -p build/dmg-staging
cp -R "$APP" build/dmg-staging/
ln -s /Applications build/dmg-staging/Applications

hdiutil create -volname "Cadence" -srcfolder build/dmg-staging \
    -ov -format UDZO "$DMG"

rm -rf build/dmg-staging

echo "Built $DMG"
