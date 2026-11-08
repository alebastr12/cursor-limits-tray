#!/usr/bin/env bash
# Build TrayAILimits.app and zip it for GitHub Releases.
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
ZIP="$DIST/TrayAILimits-${VERSION}.zip"

rm -f "$ZIP"
# ditto preserves .app structure and resource forks better than zip -r
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

# Also keep a stable name for scripts / CI
cp -f "$ZIP" "$DIST/TrayAILimits-macOS.zip"

echo "Packed $ZIP"
echo "Also: $DIST/TrayAILimits-macOS.zip"
ls -lh "$ZIP" "$DIST/TrayAILimits-macOS.zip"
