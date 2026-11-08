#!/usr/bin/env bash
# Build a drag-to-Applications .dmg (ad-hoc signed .app, not notarized).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  VERSION="$(git describe --tags --always --dirty 2>/dev/null || echo "0.2.7")"
  VERSION="${VERSION#v}"
fi

./Scripts/build-app.sh

DIST="$ROOT/dist"
APP="$DIST/TrayAILimits.app"
STAGE="$DIST/dmg-stage"
VOL="Tray AI limits"
DMG_TMP="$DIST/TrayAILimits-${VERSION}-tmp.dmg"
DMG="$DIST/TrayAILimits-${VERSION}.dmg"

rm -rf "$STAGE" "$DMG_TMP" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# ~160MB RW image is plenty for this tiny binary; hdiutil will compact on convert.
SIZE_MB=64
hdiutil create \
  -volname "$VOL" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDRW \
  -size "${SIZE_MB}m" \
  "$DMG_TMP" >/dev/null

# Compact to compressed UDZO for distribution
hdiutil convert "$DMG_TMP" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
rm -f "$DMG_TMP"
rm -rf "$STAGE"

# Stable alias
cp -f "$DMG" "$DIST/TrayAILimits-macOS.dmg"

echo "Built $DMG"
echo "Also: $DIST/TrayAILimits-macOS.dmg"
ls -lh "$DMG" "$DIST/TrayAILimits-macOS.dmg"
