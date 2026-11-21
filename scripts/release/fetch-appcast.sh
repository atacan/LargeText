#!/usr/bin/env bash
# Downloads appcast.xml from the latest published release and prints the next build number: the highest
# sparkle:version in it plus one, or 1 when there is no release yet.
#
# Environment: GH_TOKEN (or a logged-in `gh`), GITHUB_REPOSITORY.
# Outputs (GITHUB_OUTPUT): appcast_path (empty when there is no release yet), build_number.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

require_command gh

DOWNLOAD_DIR="$RELEASE_WORK_ROOT/previous-appcast"
mkdir -p "$DOWNLOAD_DIR"
rm -f "$DOWNLOAD_DIR/appcast.xml"

appcast_path=""
if gh release view --repo "$GITHUB_REPOSITORY" --json tagName >/dev/null 2>&1; then
  latest_tag="$(gh release view --repo "$GITHUB_REPOSITORY" --json tagName --jq .tagName)"
  log "Downloading appcast.xml from $latest_tag"
  gh release download "$latest_tag" --repo "$GITHUB_REPOSITORY" --pattern appcast.xml --dir "$DOWNLOAD_DIR" ||
    fail "the latest release $latest_tag has no appcast.xml asset; every release must carry the whole feed"
  appcast_path="$DOWNLOAD_DIR/appcast.xml"
else
  log "No published release yet; starting a new appcast"
fi

max_build=0
if [[ -n "$appcast_path" ]]; then
  while IFS= read -r build; do
    [[ "$build" -gt "$max_build" ]] && max_build="$build"
  done < <(sed -n \
    -e 's/.*<sparkle:version>\([0-9][0-9]*\)<\/sparkle:version>.*/\1/p' \
    -e 's/.*sparkle:version="\([0-9][0-9]*\)".*/\1/p' \
    "$appcast_path")
fi

set_output appcast_path "$appcast_path"
set_output build_number "$((max_build + 1))"
