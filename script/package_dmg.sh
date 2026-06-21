#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/BatteryHub.xcodeproj"
SCHEME="BatteryHubMac"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/build/DerivedData}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
STAGING_DIR="$ROOT_DIR/build/dmg-staging"
APP_NAME="BatteryHubMac.app"
VOLUME_NAME="${VOLUME_NAME:-BatteryHub}"
DMG_NAME="${DMG_NAME:-BatteryHub.dmg}"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME"
DMG_PATH="$DIST_DIR/$DMG_NAME"
ENTITLEMENTS="$ROOT_DIR/BatteryHub/Mac/BatteryHubMac.entitlements"
RESOLVED_ENTITLEMENTS="$ROOT_DIR/build/BatteryHubMac.resolved.entitlements"

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
    echo "Signing with Developer ID identity: $DEVELOPER_ID_IDENTITY"
    /usr/bin/codesign \
      --force \
      --deep \
      --options runtime \
      --timestamp \
      --sign "$DEVELOPER_ID_IDENTITY" \
      --entitlements "$entitlements" \
      "$app"
  else
    echo "No DEVELOPER_ID_IDENTITY set; using ad-hoc signing for local family testing."
    /usr/bin/codesign \
      --force \
      --deep \
      --sign - \
      --entitlements "$entitlements" \
      "$app"
  fi
}

prepare_entitlements() {
  /bin/cp "$ENTITLEMENTS" "$RESOLVED_ENTITLEMENTS"
}

notarize_dmg_if_requested() {
  local dmg="$1"

  if [[ "${NOTARIZE:-0}" != "1" ]]; then
    return
  fi

  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    echo "Submitting DMG for notarization with keychain profile: $NOTARY_PROFILE"
    /usr/bin/xcrun notarytool submit "$dmg" \
      --keychain-profile "$NOTARY_PROFILE" \
      --wait

    echo "Stapling notarization ticket..."
    /usr/bin/xcrun stapler staple "$dmg"
    return
  fi

  if [[ -z "${APPLE_ID:-}" || -z "${APPLE_APP_PASSWORD:-}" || -z "${TEAM_ID:-}" ]]; then
    echo "NOTARIZE=1 requires NOTARY_PROFILE, or APPLE_ID, APPLE_APP_PASSWORD, and TEAM_ID." >&2
    exit 1
  fi

  echo "Submitting DMG for notarization..."
  /usr/bin/xcrun notarytool submit "$dmg" \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_APP_PASSWORD" \
    --team-id "$TEAM_ID" \
    --wait

  echo "Stapling notarization ticket..."
  /usr/bin/xcrun stapler staple "$dmg"
}

require_tool xcodebuild
require_tool hdiutil
require_tool codesign

mkdir -p "$DIST_DIR"
rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR"

echo "Building $SCHEME ($CONFIGURATION)..."
/usr/bin/xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "platform=macOS,arch=arm64" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  build

if [[ ! -d "$APP_PATH" ]]; then
  echo "Built app not found: $APP_PATH" >&2
  exit 1
fi

echo "Preparing DMG staging folder..."
/usr/bin/ditto "$APP_PATH" "$STAGING_DIR/$APP_NAME"
/bin/ln -s /Applications "$STAGING_DIR/Applications"
/usr/bin/xattr -dr com.apple.quarantine "$STAGING_DIR/$APP_NAME" 2>/dev/null || true

prepare_entitlements
sign_app "$STAGING_DIR/$APP_NAME" "$RESOLVED_ENTITLEMENTS"

echo "Verifying code signature..."
/usr/bin/codesign --verify --deep --strict --verbose=2 "$STAGING_DIR/$APP_NAME"

echo "Creating DMG: $DMG_PATH"
/usr/bin/hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$DMG_PATH"

notarize_dmg_if_requested "$DMG_PATH"

echo "Package ready: $DMG_PATH"
echo
if [[ -n "${DEVELOPER_ID_IDENTITY:-}" ]]; then
  echo "Developer ID signed. For a fully trusted download, run with NOTARIZE=1 and notarization credentials."
else
  echo "Ad-hoc signed. This is fine for local testing, but another Mac may still need Gatekeeper override."
fi
