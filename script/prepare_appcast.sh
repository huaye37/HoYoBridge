#!/usr/bin/env bash
set -euo pipefail
# Never publishes anything. Use a dedicated directory containing signed release ZIPs.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_DIR="${1:?Usage: bash script/prepare_appcast.sh RELEASE_DIRECTORY HTTPS_DOWNLOAD_PREFIX}"
DOWNLOAD_PREFIX="${2:?Provide an immutable HTTPS release download prefix}"
[[ -d "$RELEASE_DIR" && "$DOWNLOAD_PREFIX" == https://* ]] || exit 2
TOOL="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"
[[ -x "$TOOL" ]] || { echo 'Resolve Swift packages first.' >&2; exit 2; }
KEY_TOOL="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin/generate_keys"
SIGN_TOOL="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin/sign_update"
EXPECTED_KEY="${MGB_SPARKLE_PUBLIC_KEY:-11DmpJkJzf0x4UdHl65GWxNMwMyu702GStGKU6p18Lw=}"
ACTUAL_KEY="$("$KEY_TOOL" --account hoyobridge-updates -p)"
[[ "$ACTUAL_KEY" == "$EXPECTED_KEY" ]] || { echo 'Sparkle signing key does not match the configured public key.' >&2; exit 1; }
"$TOOL" --account hoyobridge-updates --maximum-deltas 0 \
  --download-url-prefix "$DOWNLOAD_PREFIX" "$RELEASE_DIR"
"$SIGN_TOOL" --account hoyobridge-updates --verify "$RELEASE_DIR/appcast.xml"
echo 'Appcast generated locally. Verify signatures and hosted download links before publishing.'
