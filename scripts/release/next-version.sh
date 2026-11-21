#!/usr/bin/env bash
# Prints the next marketing version from the newest vX.Y.Z git tag.
#
# Usage: scripts/release/next-version.sh patch|minor|major
#
# With no release tag yet, prints FIRST_VERSION (default 0.1.0) whatever the bump. Needs the tags fetched
# (actions/checkout with fetch-depth: 0, or `git fetch --tags`).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

BUMP="${1:-}"
FIRST_VERSION="${FIRST_VERSION:-0.1.0}"

case "$BUMP" in
  patch|minor|major) ;;
  *) fail "usage: $0 patch|minor|major" ;;
esac

latest_tag="$(git -C "$REPO_ROOT" tag --list 'v[0-9]*.[0-9]*.[0-9]*' --sort=-version:refname | head -n 1)"
if [[ -z "$latest_tag" ]]; then
  log "No release tag yet; first version is $FIRST_VERSION"
  printf '%s\n' "$FIRST_VERSION"
  exit 0
fi

current="${latest_tag#v}"
is_semver "$current" || fail "latest tag $latest_tag is not vX.Y.Z"

IFS=. read -r major minor patch <<<"$current"
case "$BUMP" in
  patch) patch=$((patch + 1)) ;;
  minor) minor=$((minor + 1)); patch=0 ;;
  major) major=$((major + 1)); minor=0; patch=0 ;;
esac

log "Latest release is $latest_tag; $BUMP bump"
printf '%s.%s.%s\n' "$major" "$minor" "$patch"
