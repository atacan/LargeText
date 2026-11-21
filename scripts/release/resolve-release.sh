#!/usr/bin/env bash
# Decides whether and what to release, for .github/workflows/release.yml.
#
# For a push to main it finds the merged pull request of GITHUB_SHA and reads it:
#   - label `skip-release`               → no release
#   - label `release:major` / `release:minor` → that bump, otherwise patch
#   - a "## Release notes" section in the description → the notes, otherwise the PR title
# A push without a pull request (a direct push) is a patch release with the commit subject as notes.
#
# For workflow_dispatch it uses INPUT_BUMP and INPUT_NOTES (falling back to the HEAD commit subject).
#
# Environment: GITHUB_EVENT_NAME, GITHUB_SHA, GH_TOKEN (for `gh api`), INPUT_BUMP, INPUT_NOTES.
# Outputs (GITHUB_OUTPUT): skip, bump, version, notes_path, pr_number.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

require_command gh
require_command jq
require_env GITHUB_SHA

NOTES_PATH="$RELEASE_WORK_ROOT/release-notes.md"
mkdir -p "$RELEASE_WORK_ROOT"

# The body of a "Release notes" heading (any level), up to the next heading, without HTML comments (the PR
# template's hints) and without surrounding blank lines.
extract_release_notes() {
  awk '
    BEGIN { in_section = 0; in_comment = 0 }
    /^#+[[:space:]]*[Rr]elease [Nn]otes[[:space:]]*$/ { in_section = 1; next }
    in_section && /^#+[[:space:]]/ { exit }
    in_section { print }
  ' | perl -0pe 's/<!--.*?-->//gs; s/\A\s+//; s/\s+\z/\n/'
}

bump="patch"
skip="false"
pr_number=""
notes=""

if [[ "${GITHUB_EVENT_NAME:-}" == "workflow_dispatch" ]]; then
  bump="${INPUT_BUMP:-patch}"
  notes="${INPUT_NOTES:-}"
  [[ -n "${notes//[[:space:]]/}" ]] || notes="$(git -C "$REPO_ROOT" log -1 --format=%s "$GITHUB_SHA")"
else
  pr_json="$(gh api "repos/$GITHUB_REPOSITORY/commits/$GITHUB_SHA/pulls" --jq '[.[] | select(.merged_at != null)] | first // empty')"
  if [[ -z "$pr_json" ]]; then
    log "No merged pull request for $GITHUB_SHA; releasing it as a patch"
    notes="$(git -C "$REPO_ROOT" log -1 --format=%s "$GITHUB_SHA")"
  else
    pr_number="$(jq -r '.number' <<<"$pr_json")"
    labels="$(jq -r '[.labels[].name] | join(",")' <<<"$pr_json")"
    log "Pull request #$pr_number, labels: ${labels:-none}"
    case ",$labels," in
      *,skip-release,*) skip="true" ;;
    esac
    case ",$labels," in
      *,release:major,*) bump="major" ;;
      *,release:minor,*) bump="minor" ;;
    esac
    notes="$(jq -r '.body // ""' <<<"$pr_json" | tr -d '\r' | extract_release_notes)"
    [[ -n "${notes//[[:space:]]/}" ]] || notes="$(jq -r '.title' <<<"$pr_json")"
  fi
fi

case "$bump" in
  patch|minor|major) ;;
  *) fail "invalid bump '$bump'" ;;
esac

set_output skip "$skip"
set_output pr_number "$pr_number"
if [[ "$skip" == "true" ]]; then
  log "Labelled skip-release; nothing to do"
  exit 0
fi

version="$("$REPO_ROOT/scripts/release/next-version.sh" "$bump")"
printf '%s\n' "$notes" >"$NOTES_PATH"

set_output bump "$bump"
set_output version "$version"
set_output notes_path "$NOTES_PATH"
log "Release notes:"
cat "$NOTES_PATH" >&2
