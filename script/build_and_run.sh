#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="BatteryHubMac"
BUNDLE_ID="com.isaacyslin.BatteryHub.mac"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/BatteryHub.xcodeproj"
SCHEME="BatteryHubMac"
DESTINATION="platform=macOS"

usage() {
  echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
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
  /usr/bin/xattr -dr com.apple.quarantine "$bundle" 2>/dev/null || true
  /usr/bin/codesign --force --deep --sign - "$bundle" >/dev/null 2>&1 || true
  /usr/bin/open -n "$bundle"
}

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

xcodebuild -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -configuration Debug \
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
  *)
    usage
    exit 2
    ;;
esac
