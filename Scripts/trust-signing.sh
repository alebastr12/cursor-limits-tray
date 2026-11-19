#!/usr/bin/env bash
# Trust the local "TrayAILimits Dev" certificate for the current user.
#
# This writes to the **user** trust settings (login keychain), so it does NOT
# need an administrator password. System-wide trust (`security add-trusted-cert -d`)
# would need admin, but is not required for local builds.
#
# Gatekeeper still requires right-click → Open for downloaded, non-notarized apps.
set -euo pipefail

IDENTITY_NAME="${TRAY_SIGN_IDENTITY:-TrayAILimits Dev}"
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if ! security find-certificate -c "$IDENTITY_NAME" -p > "$TMP/cert.pem" 2>/dev/null; then
  echo "Certificate '$IDENTITY_NAME' not found." >&2
  echo "Run ./Scripts/setup-signing.sh first." >&2
  exit 1
fi

# No -d: user trust domain. May ask for the login keychain password if locked,
# but not for an administrator password.
security add-trusted-cert \
  -r trustRoot \
  -p codeSign \
  -k "$KEYCHAIN" \
  "$TMP/cert.pem"

echo "Trusted '$IDENTITY_NAME' for the current user (no admin required)."
echo "This does not notarize the app: downloaded builds may still need right-click → Open."
