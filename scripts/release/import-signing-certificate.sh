#!/usr/bin/env bash
# CI only: imports the Developer ID Application certificate into a temporary keychain that codesign can use
# without a password prompt, and writes the App Store Connect API key for notarytool.
#
# Required environment:
#   DEVELOPER_ID_P12_BASE64     base64 of the exported .p12 (certificate + private key).
#   DEVELOPER_ID_P12_PASSWORD   Its export password.
#   ASC_KEY_P8_BASE64           base64 of the App Store Connect API key (AuthKey_XXXX.p8).
# Outputs (GITHUB_OUTPUT): keychain_path, asc_key_path.
#
# The workflow's last step deletes the keychain and the key, even when the release failed.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

require_env DEVELOPER_ID_P12_BASE64
require_env DEVELOPER_ID_P12_PASSWORD
require_env ASC_KEY_P8_BASE64
require_env RUNNER_TEMP

KEYCHAIN_PATH="$RUNNER_TEMP/release-signing.keychain-db"
KEYCHAIN_PASSWORD="$(uuidgen)"
P12_PATH="$RUNNER_TEMP/developer-id.p12"
ASC_KEY_PATH="$RUNNER_TEMP/AuthKey.p8"

printf '%s' "$DEVELOPER_ID_P12_BASE64" | base64 --decode >"$P12_PATH"
printf '%s' "$ASC_KEY_P8_BASE64" | base64 --decode >"$ASC_KEY_PATH"
chmod 600 "$P12_PATH" "$ASC_KEY_PATH"

log "Creating a temporary keychain"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security import "$P12_PATH" -k "$KEYCHAIN_PATH" -P "$DEVELOPER_ID_P12_PASSWORD" -f pkcs12 \
  -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" >/dev/null
# Search the new keychain first, then the existing ones (for Apple's intermediate certificates).
existing="$(security list-keychains -d user | tr -d '"' | xargs)"
# shellcheck disable=SC2086
security list-keychains -d user -s "$KEYCHAIN_PATH" $existing
rm -f "$P12_PATH"

security find-identity -v -p codesigning "$KEYCHAIN_PATH" | grep -F "Developer ID Application" >/dev/null ||
  fail "the .p12 has no valid Developer ID Application identity (is the certificate chain complete?)"

set_output keychain_path "$KEYCHAIN_PATH"
set_output asc_key_path "$ASC_KEY_PATH"
