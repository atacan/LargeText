# shellcheck shell=bash
# Shared by the release scripts; source it, don't run it. Works with macOS's /bin/bash 3.2.
#
# Every script takes its inputs from the environment (documented in its header) so the same steps run in
# GitHub Actions (.github/workflows/release.yml) and locally (scripts/release.sh). See docs/releasing.md.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

APP_NAME="${APP_NAME:-LargeText}"
PROJECT_PATH="${PROJECT_PATH:-$REPO_ROOT/xcode/LargeText/LargeText.xcodeproj}"
SCHEME="${SCHEME:-LargeText}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-atacan/LargeText}"
RELEASE_WORK_ROOT="${RELEASE_WORK_ROOT:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/largetext-release}"
RELEASE_WORK_ROOT="${RELEASE_WORK_ROOT%/}"
DERIVED_DATA_DIR="${DERIVED_DATA_DIR:-$RELEASE_WORK_ROOT/DerivedData}"
SPARKLE_BIN="${SPARKLE_BIN:-$DERIVED_DATA_DIR/SourcePackages/artifacts/sparkle/Sparkle/bin}"

log() {
  printf '\n==> %s\n' "$*" >&2
}

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

require_env() {
  local name="$1"
  [[ -n "${!name:-}" ]] || fail "missing required environment variable: $name"
}

require_file() {
  [[ -f "$1" ]] || fail "missing required file: $1"
}

# Writes `name=value` to $GITHUB_OUTPUT (GitHub's step output file, or the file scripts/release.sh reads)
# and echoes it to stderr for the log. Multi-line values use the heredoc form GitHub documents.
set_output() {
  local name="$1"
  local value="$2"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    if [[ "$value" == *$'\n'* ]]; then
      local delimiter
      delimiter="EOF_$(uuidgen)"
      printf '%s<<%s\n%s\n%s\n' "$name" "$delimiter" "$value" "$delimiter" >>"$GITHUB_OUTPUT"
    else
      printf '%s=%s\n' "$name" "$value" >>"$GITHUB_OUTPUT"
    fi
  fi
  printf '%s=%s\n' "$name" "$value" >&2
}

is_semver() {
  [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

dmg_filename() {
  printf '%s-%s.dmg' "$APP_NAME" "$1"
}

# Where GitHub serves a release asset for tag v<version>.
release_download_prefix() {
  printf 'https://github.com/%s/releases/download/v%s/' "$GITHUB_REPOSITORY" "$1"
}

# The feed every shipped copy of the app reads (SPARKLE_FEED_URL in the Xcode project): always the newest
# published, non-prerelease release's appcast.xml.
latest_appcast_url() {
  printf 'https://github.com/%s/releases/latest/download/appcast.xml' "$GITHUB_REPOSITORY"
}
