#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="HoYoBridge"
PROCESS_NAME="MacGameBridge"
PRODUCT_NAME="MacGameBridge"
BUNDLE_ID="cn.yeutech.MacGameBridge"
MIN_SYSTEM_VERSION="26.0"
BUILD_CONFIGURATION="${MGB_BUILD_CONFIGURATION:-debug}"
APP_VERSION="${MGB_APP_VERSION:-0.1.0}"
if [[ ! "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "MGB_APP_VERSION must be a numeric major.minor.patch version" >&2
  exit 2
fi
case "$BUILD_CONFIGURATION" in debug|release) ;; *) exit 2 ;; esac

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$PROCESS_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

pkill -x "$PROCESS_NAME" >/dev/null 2>&1 || true

cd "$ROOT_DIR"
bash "$ROOT_DIR/script/build_native_window_adapter.sh"
env -u PROTOC_PATH swift build -c "$BUILD_CONFIGURATION" --product "$PRODUCT_NAME"
BUILD_BINARY="$ROOT_DIR/.build/$BUILD_CONFIGURATION/$PRODUCT_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES/RuntimeAssets"
cp "$BUILD_BINARY" "$APP_BINARY"
SPARKLE_ROOT="$ROOT_DIR/.build/artifacts/sparkle/Sparkle"
mkdir -p "$APP_CONTENTS/Frameworks"
/usr/bin/ditto "$SPARKLE_ROOT/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" "$APP_CONTENTS/Frameworks/Sparkle.framework"
cp -R "$ROOT_DIR/.build/$BUILD_CONFIGURATION/MacGameBridge_BridgeStatus.bundle" "$APP_RESOURCES/"
ICONSET_DIR="$ROOT_DIR/.build/LauncherApp.iconset"
mkdir -p "$ICONSET_DIR"
for icon_size in 16 32 128 256 512; do
  /usr/bin/sips -z "$icon_size" "$icon_size" "$ROOT_DIR/Assets/AppIcon.png" \
    --out "$ICONSET_DIR/icon_${icon_size}x${icon_size}.png" >/dev/null
  retina_size=$((icon_size * 2))
  /usr/bin/sips -z "$retina_size" "$retina_size" "$ROOT_DIR/Assets/AppIcon.png" \
    --out "$ICONSET_DIR/icon_${icon_size}x${icon_size}@2x.png" >/dev/null
done
/usr/bin/iconutil -c icns "$ICONSET_DIR" -o "$APP_RESOURCES/AppIcon.icns"
chmod +x "$APP_BINARY"
cp "$ROOT_DIR/THIRD_PARTY_NOTICES.md" "$APP_RESOURCES/THIRD_PARTY_NOTICES.md"
cp -R "$ROOT_DIR/LICENSES" "$APP_RESOURCES/LICENSES"
cp "$ROOT_DIR/.build/checkouts/Sparkle/LICENSE" "$APP_RESOURCES/LICENSES/Sparkle.txt"

copy_verified_asset() {
  local source="$1"
  local destination_name="$2"
  local expected_size="$3"
  local expected_sha256="$4"

  test -f "$source"
  test "$(stat -f '%z' "$source")" = "$expected_size"
  test "$(shasum -a 256 "$source" | awk '{print $1}')" = "$expected_sha256"
  cp "$source" "$APP_RESOURCES/RuntimeAssets/$destination_name"
  test "$(stat -f '%z' "$APP_RESOURCES/RuntimeAssets/$destination_name")" = "$expected_size"
  test "$(shasum -a 256 "$APP_RESOURCES/RuntimeAssets/$destination_name" | awk '{print $1}')" = "$expected_sha256"
}

copy_verified_asset \
  "$ROOT_DIR/LocalRuntimes/Downloads/wine-crossover-11.0-1-osx64-signed.tar.xz" \
  "wine-crossover-11.0-1-osx64-signed.tar.xz" \
  "456021524" \
  "89fa7e90fb626523a90d5867a03c6be785d017176739c6320a3b86c7838c3a35"
copy_verified_asset \
  "$ROOT_DIR/LocalRuntimes/RuntimeAssets/dxmt-v0.80-builtin.tar.gz" \
  "dxmt-v0.80-builtin.tar.gz" \
  "18681669" \
  "8f260e36b5739e68f3bad613381441385c4dc7b85b78ba8de653d5a6a264529d"
STEAM_ASSET_ROOT="$ROOT_DIR/LocalRuntimes/Tools/YAAGL-ca78abc/sidecar/protonextras"
copy_verified_asset "$ROOT_DIR/LocalRuntimes/Tools/YAAGL-ca78abc/sidecar/7z/7zz" "7zz" "5229328" \
  "10bba361f87be5882e362df8f283646fb5fff1a7f63246149a5809be286897f5"
cp "$ROOT_DIR/LocalRuntimes/Tools/YAAGL-ca78abc/sidecar/7z/License.txt" "$APP_RESOURCES/LICENSES/7-Zip.txt"
copy_verified_asset "$STEAM_ASSET_ROOT/steam64.exe" "steam64.exe" "111304" \
  "0424339444c54bf1f9fdbadf12e4e2c90ceef41d987fe573b93f5f2ebfd8a657"
copy_verified_asset "$STEAM_ASSET_ROOT/steam32.exe" "steam32.exe" "97904" \
  "d3b17fda25217165f5f5198ac179bb0645d4fcc61381bfeb0ba3c73ea029a433"
copy_verified_asset "$STEAM_ASSET_ROOT/lsteamclient64.dll" "lsteamclient64.dll" "5560872" \
  "af50ed0d952ef98d99d4d3ff67b4836b545c9403894430fca31969f9f630637b"
copy_verified_asset "$STEAM_ASSET_ROOT/lsteamclient32.dll" "lsteamclient32.dll" "4412824" \
  "608eece6672369db539211fd04eb95b9fb5ddd077e76aa87c28c04c25c1e2fe2"

NATIVE_WINDOW_ROOT="$ROOT_DIR/LocalRuntimes/Experiments/native-window-adapter"
cp "$NATIVE_WINDOW_ROOT/libMGBWindowAdapter.dylib" \
  "$APP_RESOURCES/RuntimeAssets/libMGBWindowAdapter.dylib"
cp "$NATIVE_WINDOW_ROOT/window-flags.exe" \
  "$APP_RESOURCES/RuntimeAssets/window-flags.exe"
/usr/bin/codesign --verify "$APP_RESOURCES/RuntimeAssets/libMGBWindowAdapter.dylib"

JADEITE_ROOT="$NATIVE_WINDOW_ROOT/starrail-prefix/drive_c/mgb-jadeite"
mkdir -p "$APP_RESOURCES/RuntimeAssets/Jadeite"
copy_verified_asset "$JADEITE_ROOT/jadeite.exe" "Jadeite/jadeite.exe" "44544" \
  "b784e84924ff6e62050bf0d41272cd54a9e71881f77d4bfc8fe1fc52ed81eed9"
copy_verified_asset "$JADEITE_ROOT/game_payload.dll" "Jadeite/game_payload.dll" "36352" \
  "08dc4aff0008aa3752e58a7d922986906f7e39c34cc6b52b44394ac5cf9e1fd9"
copy_verified_asset "$JADEITE_ROOT/launcher_payload.dll" "Jadeite/launcher_payload.dll" "17408" \
  "165d7efbf854367ff06c4a2404687680765e0f5ca3acb13de84e7c4b018f65ff"
cp "$JADEITE_ROOT/LICENSE.txt" "$APP_RESOURCES/RuntimeAssets/Jadeite/LICENSE.txt"
cp "$ROOT_DIR/LocalRuntimes/Experiments/hkrpg-dxmt-nv-20260905/temporary-dispatch-block.rb" \
  "$APP_RESOURCES/RuntimeAssets/temporary-starrail-dispatch.rb"

# All game downloads are handled by the background official engine.

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$PROCESS_NAME</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_VERSION</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>星桥 HoYoBridge</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

# Keep development builds offline until a real Ed25519 public key and feed are supplied.
/usr/libexec/PlistBuddy -c 'Add :SUEnableAutomaticChecks bool false' "$INFO_PLIST"
/usr/libexec/PlistBuddy -c 'Add :SUAutomaticallyUpdate bool false' "$INFO_PLIST"
/usr/libexec/PlistBuddy -c 'Add :SUAllowsAutomaticUpdates bool false' "$INFO_PLIST"
if [[ -n "${MGB_UPDATE_FEED_URL:-}" || -n "${MGB_SPARKLE_PUBLIC_KEY:-}" ]]; then
  [[ "${MGB_UPDATE_FEED_URL:-}" == https://* && -n "${MGB_SPARKLE_PUBLIC_KEY:-}" ]] || { echo "Both HTTPS feed and Sparkle public key are required" >&2; exit 2; }
  /usr/libexec/PlistBuddy -c "Add :SUFeedURL string $MGB_UPDATE_FEED_URL" "$INFO_PLIST"
  /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $MGB_SPARKLE_PUBLIC_KEY" "$INFO_PLIST"
fi

/usr/bin/codesign --force --deep --sign - "$APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  --package)
    /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$DIST_DIR/HoYoBridge-macOS-arm64.zip"
    (cd "$DIST_DIR" && /usr/bin/shasum -a 256 HoYoBridge-macOS-arm64.zip > HoYoBridge-macOS-arm64.zip.sha256)
    ;;
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$PROCESS_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    for _ in {1..20}; do
      if pgrep -x "$PROCESS_NAME" >/dev/null; then
        exit 0
      fi
      sleep 0.1
    done
    echo "$APP_NAME did not stay running" >&2
    exit 1
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--package]" >&2
    exit 2
    ;;
esac
