#!/usr/bin/env bash
set -euo pipefail

# Local validation by default; --public additionally requires Gatekeeper acceptance.
MODE="${1:---local}"
case "$MODE" in --local|--public) ;; *) echo 'Usage: bash script/verify_release.sh [--local|--public]' >&2; exit 2 ;; esac
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
ARCHIVE="HoYoBridge-macOS-arm64.zip"
TEMP_DIR="$(mktemp -d -t hoyobridge-release)"
trap 'rmdir "$TEMP_DIR" 2>/dev/null || true' EXIT

cd "$DIST_DIR"
/usr/bin/shasum -a 256 -c "$ARCHIVE.sha256"
# Inspect the actual downloaded contents rather than the adjacent development app.
/usr/bin/ditto -x -k "$ARCHIVE" "$TEMP_DIR"
APP="$TEMP_DIR/HoYoBridge.app"
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
echo "PASS: $MODE archive validation. Does not certify game compatibility or redistribution rights."
echo "Extracted inspection copy: $TEMP_DIR"
