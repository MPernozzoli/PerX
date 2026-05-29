#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="PerX"
BUNDLE_ID="it.pernozzoli.PerX"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="${TMPDIR:-/tmp}/perx-xcode-derived-data"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug/$APP_NAME.app"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

xcodebuild \
  -scheme "$APP_NAME" \
  -project "$ROOT_DIR/PerX.xcodeproj" \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  build

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
