#!/usr/bin/env bash
# Creates the GitHub release vVERSION at TARGET_SHA with the DMG and the appcast, then publishes it as the
# latest release. It is a draft until both assets are uploaded, so the feed URL
# (releases/latest/download/appcast.xml) never points at a release without them.
#
# Required environment: VERSION, DMG_PATH, APPCAST_PATH, NOTES_PATH, TARGET_SHA, GH_TOKEN (or logged-in gh).
# Optional: PR_NUMBER (linked in the notes).
# Outputs (GITHUB_OUTPUT): release_url.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

require_command gh
require_env VERSION
require_env TARGET_SHA
require_file "${DMG_PATH:-}"
require_file "${APPCAST_PATH:-}"
[[ "$(basename "$APPCAST_PATH")" == "appcast.xml" ]] || fail "APPCAST_PATH must be named appcast.xml (the asset name the app reads)"
require_file "${NOTES_PATH:-}"

TAG="v$VERSION"
if gh release view "$TAG" --repo "$GITHUB_REPOSITORY" >/dev/null 2>&1; then
  fail "release $TAG already exists"
fi

BODY="$RELEASE_WORK_ROOT/release-body.md"
{
  cat "$NOTES_PATH"
  printf '\n## Install\n\n'
  printf -- '- Download **%s** below, open it and drag LargeText to Applications.\n' "$(basename "$DMG_PATH")"
  printf -- '- Or with Homebrew: `brew tap atacan/largetext https://github.com/%s && brew install --cask largetext`\n' "$GITHUB_REPOSITORY"
  printf -- '- Already installed? LargeText updates itself (*Check for Updates…* in the menu bar).\n'
  if [[ -n "${PR_NUMBER:-}" ]]; then
    printf '\nFrom #%s.\n' "$PR_NUMBER"
  fi
} >"$BODY"

log "Creating draft release $TAG"
gh release create "$TAG" \
  --repo "$GITHUB_REPOSITORY" \
  --target "$TARGET_SHA" \
  --title "$APP_NAME $VERSION" \
  --notes-file "$BODY" \
  --draft \
  "$DMG_PATH" \
  "$APPCAST_PATH"

log "Publishing $TAG as the latest release"
gh release edit "$TAG" --repo "$GITHUB_REPOSITORY" --draft=false --latest

release_url="$(gh release view "$TAG" --repo "$GITHUB_REPOSITORY" --json url --jq .url)"
set_output release_url "$release_url"
