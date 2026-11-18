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
# Localizations (macOS preferredLanguages → en / ru)
for lang in en ru; do
  mkdir -p "$RESOURCES/${lang}.lproj"
  cp "$ROOT/Resources/${lang}.lproj/Localizable.strings" "$RESOURCES/${lang}.lproj/"
done
chmod +x "$MACOS/CursorLimitsTray"

# Sign with a stable identity when available: ad-hoc re-signing changes the code
# identity on every build, which invalidates macOS Keychain ACLs (saved sessions
# stop loading). Override with CODESIGN_IDENTITY=...; create a local identity with
# ./Scripts/setup-signing.sh.
detect_identity() {
  if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    printf '%s' "${CODESIGN_IDENTITY}"
    return
  fi
  if security find-identity -p codesigning 2>/dev/null | grep -q '"TrayAILimits Dev"'; then
    printf '%s' "TrayAILimits Dev"
    return
  fi
  local apple
  apple="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development:/ {print $2; exit}')"
  if [[ -n "${apple}" ]]; then
    printf '%s' "${apple}"
    return
  fi
  printf ''
}

IDENTITY="$(detect_identity)"
if [[ -n "${IDENTITY}" ]]; then
  codesign --force --deep --sign "${IDENTITY}" "$APP_DIR" >/dev/null 2>&1 || {
    echo "warning: signing with '${IDENTITY}' failed; falling back to ad-hoc" >&2
    codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true
    IDENTITY=""
  }
fi
if [[ -z "${IDENTITY}" ]]; then
  codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true
  echo "warning: ad-hoc signature — saved Keychain sessions may be lost after rebuilds." >&2
  echo "         Run ./Scripts/setup-signing.sh once for a stable identity." >&2
fi

# Touch so Finder refreshes icon cache for this path
touch "$APP_DIR"

echo "Built $APP_DIR"
