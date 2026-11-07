#!/usr/bin/env bash
# Build CursorLimitsTray.app and zip it for GitHub Releases.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  VERSION="$(git describe --tags --always --dirty 2>/dev/null || echo "0.2.0")"
  VERSION="${VERSION#v}"
fi

./Scripts/build-app.sh

DIST="$ROOT/dist"
APP="$DIST/CursorLimitsTray.app"
ZIP="$DIST/CursorLimitsTray-${VERSION}.zip"

rm -f "$ZIP"
# ditto preserves .app structure and resource forks better than zip -r
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

# Also keep a stable name for scripts / CI
cp -f "$ZIP" "$DIST/CursorLimitsTray-macOS.zip"

echo "Packed $ZIP"
echo "Also: $DIST/CursorLimitsTray-macOS.zip"
ls -lh "$ZIP" "$DIST/CursorLimitsTray-macOS.zip"
