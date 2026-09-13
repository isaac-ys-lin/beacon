#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/Beacon.xcodeproj"
SCHEME="BeaconMac"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/build/DerivedData}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
STAGING_DIR="$ROOT_DIR/build/dmg-staging"
APP_NAME="BeaconMac.app"
VOLUME_NAME="${VOLUME_NAME:-Beacon}"
DMG_NAME="${DMG_NAME:-Beacon.dmg}"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME"
DMG_PATH="$DIST_DIR/$DMG_NAME"
ENTITLEMENTS="$ROOT_DIR/Beacon/Mac/BeaconMac.entitlements"
RESOLVED_ENTITLEMENTS="$ROOT_DIR/build/BeaconMac.resolved.entitlements"
CHECKS="$ROOT_DIR/script/release_checks.py"
EXPECTED_TEAM_ID="${EXPECTED_TEAM_ID:-${TEAM_ID:-}}"
export CONFIGURATION EXPECTED_TEAM_ID

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required tool: $1" >&2
    exit 1
  fi
}

sign_app() {
  local app="$1"
  local entitlements="$2"
  if [[ -n "${DEVELOPER_ID_IDENTITY:-}" ]]; then
    echo "Signing the app with the requested Developer ID identity..."
    # Beacon currently has no nested executable bundles. Refuse a changed bundle
    # layout rather than recursively applying the app's entitlements to helpers.
    python3 "$CHECKS" signing-layout "$app"
    /usr/bin/codesign --force --options runtime --timestamp \
      --sign "$DEVELOPER_ID_IDENTITY" --entitlements "$entitlements" "$app"
  else
    echo "Ad-hoc signing for local development only; this is not a distribution-verified app."
    /usr/bin/codesign --force --deep --sign - --entitlements "$entitlements" "$app"
  fi
}

notarize_dmg_if_requested() {
  local dmg="$1"
  [[ "${NOTARIZE:-0}" == "1" ]] || return 0
  local credentials=()
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    credentials=(--keychain-profile "$NOTARY_PROFILE")
  else
    credentials=(--apple-id "$APPLE_ID" --password "$APPLE_APP_PASSWORD" --team-id "$TEAM_ID")
  fi
  /usr/bin/codesign --force --timestamp --sign "$DEVELOPER_ID_IDENTITY" "$dmg"
  echo "Submitting DMG; retaining Apple's result and log separately from installation evidence..."
  local submission_status=0
  /usr/bin/xcrun notarytool submit "$dmg" "${credentials[@]}" --wait --output-format json \
    > "$dmg.notary.json" || submission_status=$?
  local submission_id
  submission_id="$(python3 "$CHECKS" notary-id "$dmg.notary.json")"
  /usr/bin/xcrun notarytool log "$submission_id" "${credentials[@]}" > "$dmg.notary-log.json"
  if [[ "$submission_status" != "0" ]]; then
    echo "Notarization failed; inspect the retained Apple result/log. No success evidence was written." >&2
    return "$submission_status"
  fi
  python3 "$CHECKS" notary-result "$dmg.notary.json" >/dev/null
  /usr/bin/xcrun stapler staple "$dmg"
  python3 "$CHECKS" artifact "$dmg" --team "$EXPECTED_TEAM_ID" --output "$dmg.verification.json"
}

require_tool python3
# Credential/configuration checks precede builds and removal of any old package.
python3 "$CHECKS" preflight
case "$DMG_NAME" in
  */*|.*|"") echo "DMG_NAME must be a non-hidden filename, not a path." >&2; exit 1 ;;
esac
[[ "$DMG_NAME" == *.dmg ]] || { echo "DMG_NAME must end in .dmg" >&2; exit 1; }
require_tool xcodebuild
require_tool hdiutil
require_tool codesign
SOURCE_COMMIT="$(git -C "$ROOT_DIR" rev-parse HEAD)"
if [[ "${NOTARIZE:-0}" == "1" && -n "$(git -C "$ROOT_DIR" status --porcelain --untracked-files=normal)" ]]; then
  echo "Formal packaging requires a clean source checkout so the signed commit is traceable." >&2
  exit 1
fi

mkdir -p "$DIST_DIR"
# Never leave an old passing report beside a newly failed or different package.
rm -f "$DMG_PATH.verification.json" "$DMG_PATH.notary.json" "$DMG_PATH.notary-log.json"
rm -rf "$STAGING_DIR"
rm -f "$DMG_PATH"
mkdir -p "$STAGING_DIR"

echo "Building $SCHEME ($CONFIGURATION)..."
/usr/bin/xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIGURATION" \
  -destination "platform=macOS,arch=arm64" -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO build
[[ -d "$APP_PATH" ]] || { echo "Built app not found: $APP_PATH" >&2; exit 1; }

echo "Preparing DMG staging folder..."
/usr/bin/ditto "$APP_PATH" "$STAGING_DIR/$APP_NAME"
/bin/ln -s /Applications "$STAGING_DIR/Applications"
# Stamp only the staging copy, before signing. Do not alter source or strip quarantine.
python3 - "$STAGING_DIR/$APP_NAME/Contents/Info.plist" "$SOURCE_COMMIT" <<'PY'
from pathlib import Path
import plistlib, sys
path = Path(sys.argv[1]); info = plistlib.loads(path.read_bytes())
info['BeaconSourceCommit'] = sys.argv[2]
path.write_bytes(plistlib.dumps(info))
PY
/bin/cp "$ENTITLEMENTS" "$RESOLVED_ENTITLEMENTS"
sign_app "$STAGING_DIR/$APP_NAME" "$RESOLVED_ENTITLEMENTS"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$STAGING_DIR/$APP_NAME"
if [[ "${NOTARIZE:-0}" == "1" ]]; then
  python3 "$CHECKS" signature "$STAGING_DIR/$APP_NAME" --team "$EXPECTED_TEAM_ID"
fi

echo "Creating DMG: $DMG_PATH"
/usr/bin/hdiutil create -volname "$VOLUME_NAME" -srcfolder "$STAGING_DIR" -ov \
  -format UDZO -imagekey zlib-level=9 "$DMG_PATH"
notarize_dmg_if_requested "$DMG_PATH"
echo "Package created: $DMG_PATH"
if [[ "${NOTARIZE:-0}" == "1" ]]; then
  echo "Distribution security checks passed for the hashed artifact. Clean-Mac installation, runtime and relogin were NOT tested."
else
  echo "Distribution security and installation acceptance were NOT performed. Do not treat this package as a verified public release."
fi
