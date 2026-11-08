#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_DIR="$ROOT/dist/TrayAILimits.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

# Ensure AppIcon.icns exists
if [[ ! -f "$ROOT/Resources/AppIcon.icns" ]]; then
  "$ROOT/Scripts/build-icons.sh"
fi

swift build -c release --product CursorLimitsTray

BIN="$(swift build -c release --show-bin-path)/CursorLimitsTray"
rm -rf "$APP_DIR"
# Drop legacy bundle name if present
rm -rf "$ROOT/dist/CursorLimitsTray.app"
mkdir -p "$MACOS" "$RESOURCES"
cp "$BIN" "$MACOS/CursorLimitsTray"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$RESOURCES/AppIcon.icns"
cp "$ROOT/Resources/MenuBarGlyph.png" "$RESOURCES/MenuBarGlyph.png"
# Recognizable provider glyphs for menu bar (template PNGs)
mkdir -p "$RESOURCES/MenuBarProviders"
find "$ROOT/Resources/MenuBarProviders" -maxdepth 1 -name 'Provider*.png' -exec cp {} "$RESOURCES/MenuBarProviders/" \;
chmod +x "$MACOS/CursorLimitsTray"

# Ad-hoc sign so Keychain / local network prompts work more predictably.
codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

# Touch so Finder refreshes icon cache for this path
touch "$APP_DIR"

echo "Built $APP_DIR"
