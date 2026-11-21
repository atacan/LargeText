#!/usr/bin/env bash
# Adds the new release to the Sparkle feed and writes the whole feed, ready to attach to the release.
#
# Each release carries the complete appcast.xml as an asset, and the app reads
# https://github.com/<repo>/releases/latest/download/appcast.xml, so the newest release always serves every
# item. generate_appcast keeps the earlier items (and their per-tag download URLs) from PREVIOUS_APPCAST and
# signs only the new one.
#
# Required environment:
#   VERSION, BUILD_NUMBER, DMG_PATH, NOTES_PATH (Markdown)
#   One EdDSA private key source:
#     SPARKLE_ED_PRIVATE_KEY   The key from `generate_keys -x` (CI secret), passed on stdin.
#     SPARKLE_ED_KEY_FILE      A file with that key.
#     neither                  The login keychain (account SPARKLE_KEYCHAIN_ACCOUNT, default ed25519).
# Optional environment:
#   PREVIOUS_APPCAST         The feed to extend; empty for the first release.
#   SPARKLE_BIN              generate_appcast's directory. Default: the build's DerivedData.
#   APPCAST_OUTPUT           Default: $RELEASE_WORK_ROOT/out/appcast.xml
#
# Outputs (GITHUB_OUTPUT): appcast_path.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

require_env VERSION
require_env BUILD_NUMBER
require_env DMG_PATH
require_env NOTES_PATH
require_file "$DMG_PATH"
require_file "$NOTES_PATH"
[[ -x "$SPARKLE_BIN/generate_appcast" ]] || fail "generate_appcast not found in $SPARKLE_BIN (run build-dmg.sh first, or set SPARKLE_BIN)"

APPCAST_OUTPUT="${APPCAST_OUTPUT:-$RELEASE_WORK_ROOT/out/appcast.xml}"
DOWNLOAD_PREFIX="$(release_download_prefix "$VERSION")"
DMG_NAME="$(basename "$DMG_PATH")"
STAGING="$RELEASE_WORK_ROOT/appcast-$VERSION-$BUILD_NUMBER"
[[ ! -e "$STAGING" ]] || fail "$STAGING already exists; remove it or set RELEASE_WORK_ROOT"
mkdir -p "$STAGING" "$(dirname "$APPCAST_OUTPUT")"

if [[ -n "${PREVIOUS_APPCAST:-}" ]]; then
  require_file "$PREVIOUS_APPCAST"
  cp "$PREVIOUS_APPCAST" "$STAGING/appcast.xml"
  if grep -F -q "<sparkle:version>$BUILD_NUMBER</sparkle:version>" "$STAGING/appcast.xml"; then
    fail "the previous appcast already has build $BUILD_NUMBER"
  fi
fi
cp "$DMG_PATH" "$STAGING/$DMG_NAME"
# Same basename as the archive: generate_appcast embeds it as the item's Markdown release notes.
cp "$NOTES_PATH" "$STAGING/${DMG_NAME%.dmg}.md"

args=(
  --download-url-prefix "$DOWNLOAD_PREFIX"
  --embed-release-notes
  --maximum-versions 0
  --link "https://github.com/$GITHUB_REPOSITORY"
)

log "Generating the appcast"
if [[ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]]; then
  printf '%s' "$SPARKLE_ED_PRIVATE_KEY" | "$SPARKLE_BIN/generate_appcast" "${args[@]}" --ed-key-file - "$STAGING"
elif [[ -n "${SPARKLE_ED_KEY_FILE:-}" ]]; then
  require_file "$SPARKLE_ED_KEY_FILE"
  "$SPARKLE_BIN/generate_appcast" "${args[@]}" --ed-key-file "$SPARKLE_ED_KEY_FILE" "$STAGING"
else
  "$SPARKLE_BIN/generate_appcast" "${args[@]}" --account "${SPARKLE_KEYCHAIN_ACCOUNT:-ed25519}" "$STAGING"
fi

APPCAST="$STAGING/appcast.xml"
DMG_URL="$DOWNLOAD_PREFIX$DMG_NAME"
enclosure="$(grep -F "url=\"$DMG_URL\"" "$APPCAST" || true)"
[[ -n "$enclosure" ]] || fail "the appcast has no item for $DMG_URL"
# generate_appcast silently leaves an item unsigned when the private key doesn't match the app's
# SUPublicEDKey. Sparkle would then refuse the update, so stop here instead.
[[ "$enclosure" == *"sparkle:edSignature="* ]] || \
  fail "the new item isn't signed: the EdDSA private key doesn't match SUPublicEDKey in the app"
grep -F -q "<sparkle:version>$BUILD_NUMBER</sparkle:version>" "$APPCAST" || fail "the appcast has no build $BUILD_NUMBER"

cp "$APPCAST" "$APPCAST_OUTPUT"
set_output appcast_path "$APPCAST_OUTPUT"
log "Wrote $APPCAST_OUTPUT"
