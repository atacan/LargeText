#!/usr/bin/env bash
# Archives, signs with Developer ID, notarizes and staples the app, then packages it in a signed, notarized
# and stapled DMG.
#
# Required environment:
#   VERSION                 Marketing version, X.Y.Z (CFBundleShortVersionString).
#   BUILD_NUMBER            Integer build (CFBundleVersion); Sparkle compares this one.
#   Notarization, one of:
#     ASC_KEY_PATH, ASC_KEY_ID, ASC_ISSUER_ID   App Store Connect API key (.p8). Used by CI.
#     NOTARYTOOL_PROFILE                        A `xcrun notarytool store-credentials` keychain profile.
#     APPLE_ID, APPLE_APP_SPECIFIC_PASSWORD, APPLE_TEAM_ID
#
# Optional environment:
#   CODESIGN_IDENTITY       Default: "Developer ID Application" (must match exactly one identity).
#   APPLE_TEAM_ID           Default: the project's DEVELOPMENT_TEAM.
#   OUTPUT_DIR              Default: $RELEASE_WORK_ROOT/out
#   ALLOW_MISSING_SPARKLE_KEY=1   Build even though SPARKLE_PUBLIC_ED_KEY is empty (the app can't update).
#   XCODEBUILD_QUIET=0      Full xcodebuild logs.
#
# Outputs (GITHUB_OUTPUT): dmg_path, dmg_sha256, app_path.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

require_env VERSION
require_env BUILD_NUMBER
is_semver "$VERSION" || fail "VERSION must be X.Y.Z, got '$VERSION'"
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || fail "BUILD_NUMBER must be an integer, got '$BUILD_NUMBER'"

for tool in codesign ditto hdiutil plutil security spctl xcodebuild xcrun shasum; do
  require_command "$tool"
done

CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-Developer ID Application}"
OUTPUT_DIR="${OUTPUT_DIR:-$RELEASE_WORK_ROOT/out}"
XCODEBUILD_QUIET="${XCODEBUILD_QUIET:-1}"
quiet=()
[[ "$XCODEBUILD_QUIET" == "1" ]] && quiet=(-quiet)

notary_args=()
if [[ -n "${ASC_KEY_PATH:-}" ]]; then
  require_env ASC_KEY_ID
  require_env ASC_ISSUER_ID
  require_file "$ASC_KEY_PATH"
  notary_args=(--key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID")
elif [[ -n "${NOTARYTOOL_PROFILE:-}" ]]; then
  notary_args=(--keychain-profile "$NOTARYTOOL_PROFILE")
elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" && -n "${APPLE_TEAM_ID:-}" ]]; then
  notary_args=(--apple-id "$APPLE_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD" --team-id "$APPLE_TEAM_ID")
else
  fail "set ASC_KEY_PATH/ASC_KEY_ID/ASC_ISSUER_ID, NOTARYTOOL_PROFILE, or APPLE_ID/APPLE_APP_SPECIFIC_PASSWORD/APPLE_TEAM_ID"
fi

identity_count="$(security find-identity -v -p codesigning | grep -F -c "\"$CODESIGN_IDENTITY" || true)"
[[ "$identity_count" == "1" ]] || \
  fail "CODESIGN_IDENTITY '$CODESIGN_IDENTITY' matches $identity_count signing identities; it must match exactly one"

build_setting() {
  awk -v key="$1" '$1 == key && $2 == "=" { sub(/^[^=]*= /, ""); print; exit }' <<<"$BUILD_SETTINGS"
}

log "Reading build settings"
BUILD_SETTINGS="$(xcodebuild -project "$PROJECT_PATH" -scheme "$SCHEME" -configuration Release \
  -destination 'generic/platform=macOS' -showBuildSettings 2>/dev/null)"
TEAM_ID="${APPLE_TEAM_ID:-$(build_setting DEVELOPMENT_TEAM)}"
[[ -n "$TEAM_ID" ]] || fail "could not resolve DEVELOPMENT_TEAM; set APPLE_TEAM_ID"
if [[ -z "$(build_setting SPARKLE_PUBLIC_ED_KEY)" && "${ALLOW_MISSING_SPARKLE_KEY:-0}" != "1" ]]; then
  fail "SPARKLE_PUBLIC_ED_KEY is empty in the Xcode project, so this build could never update; see docs/releasing.md"
fi

WORK_DIR="$RELEASE_WORK_ROOT/build-$VERSION-$BUILD_NUMBER"
ARCHIVE_PATH="$WORK_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$WORK_DIR/export"
EXPORT_OPTIONS="$WORK_DIR/ExportOptions.plist"
APP_PATH="$EXPORT_DIR/$APP_NAME.app"
APP_ZIP="$WORK_DIR/$APP_NAME-$VERSION.zip"
DMG_PATH="$OUTPUT_DIR/$(dmg_filename "$VERSION")"
mkdir -p "$WORK_DIR" "$OUTPUT_DIR"
[[ ! -e "$ARCHIVE_PATH" ]] || fail "$ARCHIVE_PATH already exists; remove it or set RELEASE_WORK_ROOT"

log "Archiving $APP_NAME $VERSION ($BUILD_NUMBER)"
xcodebuild archive ${quiet[@]+"${quiet[@]}"} \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  -archivePath "$ARCHIVE_PATH" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$CODESIGN_IDENTITY" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  OTHER_CODE_SIGN_FLAGS=--timestamp

cat >"$EXPORT_OPTIONS" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>developer-id</string>
  <key>signingStyle</key>
  <string>manual</string>
  <key>signingCertificate</key>
  <string>$CODESIGN_IDENTITY</string>
  <key>teamID</key>
  <string>$TEAM_ID</string>
  <key>manageAppVersionAndBuildNumber</key>
  <false/>
</dict>
</plist>
EOF

log "Exporting the Developer ID app"
xcodebuild -exportArchive ${quiet[@]+"${quiet[@]}"} \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS"
[[ -d "$APP_PATH" ]] || fail "export did not produce $APP_PATH"

plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null || true; }
INFO="$APP_PATH/Contents/Info.plist"
[[ "$(plist "$INFO" CFBundleShortVersionString)" == "$VERSION" ]] || fail "exported version is not $VERSION"
[[ "$(plist "$INFO" CFBundleVersion)" == "$BUILD_NUMBER" ]] || fail "exported build is not $BUILD_NUMBER"
[[ -n "$(plist "$INFO" SUFeedURL)" ]] || fail "exported Info.plist has no SUFeedURL"
log "Feed: $(plist "$INFO" SUFeedURL)"

notarize() {
  log "Notarizing $(basename "$1")"
  xcrun notarytool submit "$1" "${notary_args[@]}" --wait --timeout 30m --output-format json \
    | tee "$1.notary.json"
  local status
  status="$(plutil -extract status raw -o - "$1.notary.json" 2>/dev/null || true)"
  if [[ "$status" != "Accepted" ]]; then
    local id
    id="$(plutil -extract id raw -o - "$1.notary.json" 2>/dev/null || true)"
    [[ -z "$id" ]] || xcrun notarytool log "$id" "${notary_args[@]}" >&2 || true
    fail "notarization of $(basename "$1") ended with status '${status:-unknown}'"
  fi
}

staple() {
  log "Stapling $(basename "$1")"
  xcrun stapler staple "$1"
  xcrun stapler validate "$1"
}

log "Verifying the app signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

ditto -c -k --keepParent "$APP_PATH" "$APP_ZIP"
notarize "$APP_ZIP"
staple "$APP_PATH"
spctl --assess --type execute --verbose=4 "$APP_PATH"

log "Creating the DMG"
# The app and an Applications link: drag to install. hdiutil needs nothing beyond macOS.
DMG_STAGING="$WORK_DIR/dmg"
mkdir -p "$DMG_STAGING"
ditto "$APP_PATH" "$DMG_STAGING/$APP_NAME.app"
ln -s /Applications "$DMG_STAGING/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGING" -fs HFS+ -format UDZO -ov "$DMG_PATH"

codesign --force --timestamp --sign "$CODESIGN_IDENTITY" "$DMG_PATH"
codesign --verify --strict --verbose=2 "$DMG_PATH"
notarize "$DMG_PATH"
staple "$DMG_PATH"
spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG_PATH"

DMG_SHA256="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
set_output app_path "$APP_PATH"
set_output dmg_path "$DMG_PATH"
set_output dmg_sha256 "$DMG_SHA256"
log "Built $DMG_PATH"
