#!/usr/bin/env bash
# Writes Casks/largetext.rb for VERSION and the DMG's SHA-256. This repository is its own Homebrew tap:
#
#   brew tap atacan/largetext https://github.com/atacan/LargeText
#   brew install --cask largetext
#
# Required environment: VERSION, DMG_SHA256.
# Optional: COMMIT=1 commits the cask and pushes it to PUSH_BRANCH (default main), retrying after a rebase
# if main moved meanwhile. A push with GITHUB_TOKEN doesn't start another workflow run.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

require_env VERSION
require_env DMG_SHA256
is_semver "$VERSION" || fail "VERSION must be X.Y.Z"
[[ "$DMG_SHA256" =~ ^[0-9a-f]{64}$ ]] || fail "DMG_SHA256 must be a SHA-256 hex digest"

CASK_PATH="$REPO_ROOT/Casks/largetext.rb"
BUNDLE_ID="com.actondon.LargeText"
mkdir -p "$(dirname "$CASK_PATH")"

cat >"$CASK_PATH" <<EOF
# Written by scripts/release/update-cask.sh on every release; edit the script, not this file.
cask "largetext" do
  version "$VERSION"
  sha256 "$DMG_SHA256"

  url "https://github.com/$GITHUB_REPOSITORY/releases/download/v#{version}/$APP_NAME-#{version}.dmg"
  name "$APP_NAME"
  desc "Type and read text in a huge overlay from any app"
  homepage "https://github.com/$GITHUB_REPOSITORY"

  livecheck do
    url "$(latest_appcast_url)"
    strategy :sparkle, &:short_version
  end

  # Sparkle updates the app in place, so \`brew upgrade\` leaves it alone.
  auto_updates true
  depends_on macos: ">= :sonoma"

  app "$APP_NAME.app"

  zap trash: [
    "~/Library/Caches/$BUNDLE_ID",
    "~/Library/HTTPStorages/$BUNDLE_ID",
    "~/Library/Preferences/$BUNDLE_ID.plist",
    "~/Library/Saved Application State/$BUNDLE_ID.savedState",
  ]
end
EOF
log "Wrote $CASK_PATH"

if [[ "${COMMIT:-0}" != "1" ]]; then
  exit 0
fi

PUSH_BRANCH="${PUSH_BRANCH:-main}"
cd "$REPO_ROOT"
git add "$CASK_PATH"
if git diff --cached --quiet; then
  log "Cask unchanged"
  exit 0
fi
git -c user.name="github-actions[bot]" -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
  commit -m "chore(cask): $APP_NAME $VERSION"

for attempt in 1 2 3; do
  if git push origin "HEAD:$PUSH_BRANCH"; then
    log "Pushed the cask to $PUSH_BRANCH"
    exit 0
  fi
  log "Push rejected (attempt $attempt); rebasing onto origin/$PUSH_BRANCH"
  git fetch origin "$PUSH_BRANCH"
  git rebase "origin/$PUSH_BRANCH"
done
fail "could not push the cask to $PUSH_BRANCH"
