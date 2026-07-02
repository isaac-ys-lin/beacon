#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="BeaconMac"
BUNDLE_ID="com.isaacyslin.Beacon.mac"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/Beacon.xcodeproj"
SCHEME="BeaconMac"
DESTINATION="platform=macOS,arch=arm64"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/build/DerivedData}"
INSTALL_PATH="/Applications/$APP_NAME.app"

# Sign with a stable Apple Development identity by default so TCC (Bluetooth,
# notifications) permissions persist across rebuilds. Ad-hoc builds get a new
# code identity every time, which makes macOS treat each build as a new app and
# accumulate stale permission entries. Override the team with
# BEACON_DEVELOPMENT_TEAM, or set it empty to fall back to an ad-hoc build.
BEACON_DEVELOPMENT_TEAM="${BEACON_DEVELOPMENT_TEAM-3YG3N2J423}"
BUILD_SIGNING_ARGS=()
if [[ -n "$BEACON_DEVELOPMENT_TEAM" ]]; then
  BUILD_SIGNING_ARGS+=(
    CODE_SIGNING_ALLOWED=YES
    CODE_SIGN_STYLE=Automatic
    DEVELOPMENT_TEAM="$BEACON_DEVELOPMENT_TEAM"
    CODE_SIGN_IDENTITY="Apple Development"
  )
fi

usage() {
  echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--verify-signing|--install]" >&2
  echo "Signs with Apple Development team $BEACON_DEVELOPMENT_TEAM by default; override with BEACON_DEVELOPMENT_TEAM (set empty for ad-hoc)." >&2
}

app_path() {
  xcodebuild -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
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
    echo "Set BEACON_DEVELOPMENT_TEAM=<team id> and make sure an Apple Development signing identity is installed." >&2
    echo "$details" >&2
    exit 1
  fi

  # Beacon must NOT be sandboxed: it shells out to ideviceinfo to read USB iPhone
  # battery, which the App Sandbox blocks. Enforced signing once silently
  # re-enabled the sandbox and broke iPhone-over-USB — refuse to ship that again.
  if grep -q "com.apple.security.app-sandbox" <<<"$details"; then
    echo "Built app is sandboxed. Refusing install: the sandbox blocks the" >&2
    echo "ideviceinfo subprocess, so USB iPhone battery never appears." >&2
    echo "Remove com.apple.security.app-sandbox from Beacon/Mac/BeaconMac.entitlements." >&2
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

unregister_launch_services_copy() {
  local bundle="$1"
  if [[ -d "$bundle" ]]; then
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
      -u -R "$bundle" >/dev/null 2>&1 || true
  fi
}

verify_running_app() {
  local expected_bundle="$1"
  local expected_executable="$expected_bundle/Contents/MacOS/$APP_NAME"
  local pid
  local command_line
  local seen_processes=()

  while read -r pid; do
    [[ -n "$pid" ]] || continue
    command_line="$(/bin/ps -p "$pid" -o command= 2>/dev/null || true)"
    seen_processes+=("pid=$pid command=$command_line")
    if [[ "$command_line" == "$expected_executable"* ]]; then
      echo "Verified active app: pid=$pid executable=$expected_executable"
      return
    fi
  done < <(/usr/bin/pgrep -x "$APP_NAME" || true)

  echo "No running $APP_NAME process matched expected executable:" >&2
  echo "  $expected_executable" >&2
  if [[ ${#seen_processes[@]} -gt 0 ]]; then
    printf 'Observed processes:\n' >&2
    printf '  %s\n' "${seen_processes[@]}" >&2
  fi
  exit 1
}

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

xcodebuild -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
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
    verify_running_app "$APP_BUNDLE"
    ;;
  --verify-signing|verify-signing)
    require_signed_bundle "$APP_BUNDLE"
    ;;
  --install|install)
    install_app "$APP_BUNDLE"
    unregister_launch_services_copy "$APP_BUNDLE"
    open_app "$INSTALL_PATH"
    sleep 1
    verify_running_app "$INSTALL_PATH"
    ;;
  *)
    usage
    exit 2
    ;;
esac
