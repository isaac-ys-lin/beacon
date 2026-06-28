#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="BeaconMac"
BUNDLE_ID="com.isaacyslin.Beacon.mac"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/Beacon.xcodeproj"
SCHEME="BeaconMac"
DESTINATION="platform=macOS,arch=arm64"
INSTALL_PATH="/Applications/$APP_NAME.app"

BUILD_SIGNING_ARGS=()
if [[ -n "${BATTERYHUB_DEVELOPMENT_TEAM:-}" ]]; then
  BUILD_SIGNING_ARGS+=(
    CODE_SIGNING_ALLOWED=YES
    CODE_SIGN_STYLE=Automatic
    DEVELOPMENT_TEAM="$BATTERYHUB_DEVELOPMENT_TEAM"
    CODE_SIGN_IDENTITY="Apple Development"
  )
fi

usage() {
  echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--verify-signing|--install]" >&2
  echo "Set BATTERYHUB_DEVELOPMENT_TEAM=<team id> to build with Apple Development signing." >&2
}

app_path() {
  xcodebuild -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -showBuildSettings 2>/dev/null |
    awk -F'= ' '
      $1 ~ /^[[:space:]]*BUILT_PRODUCTS_DIR[[:space:]]*$/ { dir=$2 }
      $1 ~ /^[[:space:]]*FULL_PRODUCT_NAME[[:space:]]*$/ { name=$2 }
      END {
        if (dir != "" && name != "") {
          print dir "/" name
        }
      }
    '
}

open_app() {
  local bundle="$1"
  local env_args=()
  if [[ -n "${BATTERYHUB_PREVIEW_DATA:-}" ]]; then
    env_args+=(--env "BATTERYHUB_PREVIEW_DATA=$BATTERYHUB_PREVIEW_DATA")
  fi
  /usr/bin/xattr -dr com.apple.quarantine "$bundle" 2>/dev/null || true
  /usr/bin/open -n ${env_args[@]+"${env_args[@]}"} "$bundle"
}

signing_details() {
  local bundle="$1"
  codesign -dvvv --entitlements :- "$bundle" 2>&1 || true
}

require_signed_bundle() {
  local bundle="$1"
  local details
  details="$(signing_details "$bundle")"

  if grep -q "Signature=adhoc" <<<"$details"; then
    echo "Built app is ad-hoc signed. Refusing formal install." >&2
    echo "Set BATTERYHUB_DEVELOPMENT_TEAM=<team id> and make sure an Apple Development signing identity is installed." >&2
    echo "$details" >&2
    exit 1
  fi
}

install_app() {
  local bundle="$1"
  local staging_path="/Applications/.$APP_NAME.app.installing.$$"
  require_signed_bundle "$bundle"
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  /bin/rm -rf "$staging_path"
  /usr/bin/ditto "$bundle" "$staging_path"
  /usr/bin/xattr -dr com.apple.quarantine "$staging_path" 2>/dev/null || true
  require_signed_bundle "$staging_path"
  if [[ -d "$INSTALL_PATH" ]]; then
    /bin/rm -rf "$INSTALL_PATH"
    echo "Removed existing app at $INSTALL_PATH"
  fi
  /bin/mv "$staging_path" "$INSTALL_PATH"
  require_signed_bundle "$INSTALL_PATH"
  echo "Installed signed app to $INSTALL_PATH"
}

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

xcodebuild -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -configuration Debug \
  ${BUILD_SIGNING_ARGS[@]+"${BUILD_SIGNING_ARGS[@]}"} \
  build

APP_BUNDLE="$(app_path)"
if [[ -z "$APP_BUNDLE" || ! -d "$APP_BUNDLE" ]]; then
  echo "Built app bundle was not found." >&2
  exit 1
fi

case "$MODE" in
  run)
    open_app "$APP_BUNDLE"
    ;;
  --debug|debug)
    lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
    ;;
  --logs|logs)
    open_app "$APP_BUNDLE"
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app "$APP_BUNDLE"
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app "$APP_BUNDLE"
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  --verify-signing|verify-signing)
    require_signed_bundle "$APP_BUNDLE"
    ;;
  --install|install)
    install_app "$APP_BUNDLE"
    open_app "$INSTALL_PATH"
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    usage
    exit 2
    ;;
esac
