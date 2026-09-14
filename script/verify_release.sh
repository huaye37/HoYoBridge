#!/usr/bin/env bash
set -euo pipefail

# Local validation by default; --public additionally requires Gatekeeper acceptance.
MODE="--local"
FORMAT="zip"
for argument in "$@"; do
  case "$argument" in
    --local|--public) MODE="$argument" ;;
    --zip) FORMAT="zip" ;;
    --dmg) FORMAT="dmg" ;;
    *) echo 'Usage: bash script/verify_release.sh [--local|--public] [--zip|--dmg]' >&2; exit 2 ;;
  esac
done
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
ARCHIVE="HoYoBridge-macOS-arm64.$FORMAT"
TEMP_DIR="$(mktemp -d -t hoyobridge-release)"
MOUNT_DIR="$TEMP_DIR/mount"
ATTACHED=false
cleanup() {
  if [[ "$ATTACHED" = true ]]; then
    /usr/bin/hdiutil detach -quiet "$MOUNT_DIR" || true
  fi
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

cd "$DIST_DIR"
/usr/bin/shasum -a 256 -c "$ARCHIVE.sha256"
if [[ "$FORMAT" = zip ]]; then
  # Inspect the actual downloaded contents rather than the adjacent development app.
  /usr/bin/ditto -x -k "$ARCHIVE" "$TEMP_DIR"
  APP="$TEMP_DIR/HoYoBridge.app"
else
  mkdir -p "$MOUNT_DIR"
  /usr/bin/hdiutil attach -quiet -nobrowse -readonly -mountpoint "$MOUNT_DIR" "$ARCHIVE"
  ATTACHED=true
  APP="$MOUNT_DIR/HoYoBridge.app"
  test -L "$MOUNT_DIR/Applications"
  test "$(/usr/bin/readlink "$MOUNT_DIR/Applications")" = /Applications
fi
PLIST="$APP/Contents/Info.plist"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")" = cn.yeutech.MacGameBridge
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$PLIST")" = '星桥 HoYoBridge'
test -x "$APP/Contents/MacOS/MacGameBridge"
/usr/bin/codesign --verify --deep --strict "$APP"
/usr/bin/lipo "$APP/Contents/MacOS/MacGameBridge" -verify_arch arm64
test -s "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
if [[ "$MODE" = --public ]]; then
  /usr/sbin/spctl --assess --type execute --verbose=2 "$APP"
  /usr/bin/xcrun stapler validate "$APP"
fi
echo "PASS: $MODE $FORMAT validation. Does not certify game compatibility or redistribution rights."
