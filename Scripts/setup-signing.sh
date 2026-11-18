#!/usr/bin/env bash
# Create a stable self-signed code-signing identity for local builds.
#
# Why: ad-hoc signing (`codesign -s -`) creates a new code identity on every
# rebuild. macOS Keychain ACLs are bound to that identity, so saved provider
# sessions become unreadable after each build. A stable identity fixes that.
#
# Usage:
#   ./Scripts/setup-signing.sh
#   CODESIGN_IDENTITY="TrayAILimits Dev" ./Scripts/build-app.sh
set -euo pipefail

IDENTITY_NAME="${TRAY_SIGN_IDENTITY:-TrayAILimits Dev}"
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"

# Self-signed certs are not "valid" for `find-identity -v` (they are not in the
# trust store), but codesign can still use them — check the full list.
if security find-identity -p codesigning 2>/dev/null | grep -q "\"${IDENTITY_NAME}\""; then
  echo "Code-signing identity already exists: ${IDENTITY_NAME}"
  echo "Build with: CODESIGN_IDENTITY=\"${IDENTITY_NAME}\" ./Scripts/build-app.sh"
  exit 0
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "openssl is required (Xcode Command Line Tools usually provide it)." >&2
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# A non-empty PKCS#12 password: macOS `security import` rejects some
# empty-password archives with "MAC verification failed".
P12_PASS="$(openssl rand -hex 16)"

openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -keyout "$TMP/key.pem" \
  -out "$TMP/cert.pem" \
  -subj "/CN=${IDENTITY_NAME}" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" >/dev/null 2>&1

# OpenSSL 3 needs -legacy for a PKCS#12 macOS `security` can read; LibreSSL
# (the system /usr/bin/openssl) does not know that flag.
if ! openssl pkcs12 -export -legacy \
      -out "$TMP/identity.p12" \
      -inkey "$TMP/key.pem" \
      -in "$TMP/cert.pem" \
      -name "$IDENTITY_NAME" \
      -passout "pass:${P12_PASS}" >/dev/null 2>&1; then
  rm -f "$TMP/identity.p12"
  openssl pkcs12 -export \
    -out "$TMP/identity.p12" \
    -inkey "$TMP/key.pem" \
    -in "$TMP/cert.pem" \
    -name "$IDENTITY_NAME" \
    -passout "pass:${P12_PASS}" >/dev/null 2>&1
fi

security import "$TMP/identity.p12" \
  -k "$KEYCHAIN" \
  -P "${P12_PASS}" \
  -T /usr/bin/codesign \
  -T /usr/bin/security >/dev/null

# Verify that codesign can actually use the private key (no UI prompt).
TEST_BIN="$TMP/sign-test-bin"
cp /bin/echo "$TEST_BIN"
if ! codesign --force --sign "$IDENTITY_NAME" "$TEST_BIN" >/dev/null 2>&1; then
  echo "Identity imported, but codesign could not use it. Check Keychain access." >&2
  exit 1
fi

echo "Created code-signing identity: ${IDENTITY_NAME}"
echo "Build with: CODESIGN_IDENTITY=\"${IDENTITY_NAME}\" ./Scripts/build-app.sh"
echo
echo "Note: switching from an ad-hoc build invalidates the old Keychain ACL once;"
echo "reconnect providers if the app asks after the first launch."
