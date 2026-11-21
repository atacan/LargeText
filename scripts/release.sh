#!/usr/bin/env bash
# Local fallback for .github/workflows/release.yml: the same steps from your Mac, for when Actions can't run.
# Normally you never need it: merging a pull request into main releases it.
#
# Usage:
#   scripts/release.sh --bump patch|minor|major --notes 'Markdown notes' [--dry-run]
#   scripts/release.sh --bump minor --notes-file notes.md
#   scripts/release.sh --bump patch <<'MARKDOWN'
#   - Fixed …
#   MARKDOWN
#
# It releases HEAD, which must be on main and pushed. It needs, on this Mac:
#   - the Developer ID Application certificate in the login keychain (CODESIGN_IDENTITY to pick one),
#   - NOTARYTOOL_PROFILE, a `xcrun notarytool store-credentials` profile (or the ASC_* / APPLE_ID variables
#     build-dmg.sh documents),
#   - the Sparkle private key in the login keychain (from `generate_keys`), or SPARKLE_ED_KEY_FILE,
#   - `gh` logged in with push access.
# --dry-run prints the version and build it would release, and stops before building.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/release/common.sh"

BUMP=""
NOTES=""
NOTES_FILE=""
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bump) BUMP="${2:-}"; shift 2 ;;
    --notes) NOTES="${2:-}"; shift 2 ;;
    --notes-file) NOTES_FILE="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) fail "unknown argument: $1" ;;
  esac
done

case "$BUMP" in
  patch|minor|major) ;;
  *) fail "--bump patch|minor|major is required" ;;
esac

if [[ -n "$NOTES_FILE" ]]; then
  require_file "$NOTES_FILE"
  NOTES="$(<"$NOTES_FILE")"
elif [[ -z "$NOTES" && ! -t 0 ]]; then
  NOTES="$(cat)"
fi
[[ -n "${NOTES//[[:space:]]/}" ]] || fail "release notes are required (--notes, --notes-file or stdin)"

cd "$REPO_ROOT"
[[ "$(git branch --show-current)" == "main" ]] || fail "check out main first"
[[ -z "$(git status --porcelain)" ]] || fail "the working tree has changes"
git fetch --tags --quiet origin main
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || fail "HEAD is not origin/main; pull or push first"

RELEASE_WORK_ROOT="$RELEASE_WORK_ROOT/$(date -u +%Y%m%dT%H%M%SZ)"
export RELEASE_WORK_ROOT
mkdir -p "$RELEASE_WORK_ROOT"
# The step scripts write `name=value` outputs here, as they do to GitHub's output file in Actions.
export GITHUB_OUTPUT="$RELEASE_WORK_ROOT/outputs.env"
: >"$GITHUB_OUTPUT"
output() { awk -F= -v key="$1" '$1 == key { sub(/^[^=]*=/, ""); value = $0 } END { print value }' "$GITHUB_OUTPUT"; }

VERSION="$(scripts/release/next-version.sh "$BUMP")"
scripts/release/fetch-appcast.sh >/dev/null
BUILD_NUMBER="$(output build_number)"
PREVIOUS_APPCAST="$(output appcast_path)"
NOTES_PATH="$RELEASE_WORK_ROOT/release-notes.md"
printf '%s\n' "$NOTES" >"$NOTES_PATH"

log "Releasing $APP_NAME $VERSION ($BUILD_NUMBER) from $(git rev-parse --short HEAD)"
if [[ "$DRY_RUN" == "1" ]]; then
  printf 'version=%s\nbuild=%s\nprevious_appcast=%s\nwork_root=%s\n' \
    "$VERSION" "$BUILD_NUMBER" "${PREVIOUS_APPCAST:-none}" "$RELEASE_WORK_ROOT"
  exit 0
fi

export VERSION BUILD_NUMBER NOTES_PATH PREVIOUS_APPCAST
scripts/release/build-dmg.sh
export DMG_PATH DMG_SHA256 APPCAST_PATH TARGET_SHA
DMG_PATH="$(output dmg_path)"
DMG_SHA256="$(output dmg_sha256)"

scripts/release/update-appcast.sh
APPCAST_PATH="$(output appcast_path)"
TARGET_SHA="$(git rev-parse HEAD)"

scripts/release/publish-release.sh
COMMIT=1 scripts/release/update-cask.sh
log "Released $APP_NAME $VERSION"
