#!/usr/bin/env bash
set -euo pipefail
# Never publishes anything. Use a dedicated directory containing signed release ZIPs.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_DIR="${1:?Usage: bash script/prepare_appcast.sh RELEASE_DIRECTORY HTTPS_DOWNLOAD_PREFIX}"
DOWNLOAD_PREFIX="${2:?Provide an immutable HTTPS release download prefix}"
[[ -d "$RELEASE_DIR" && "$DOWNLOAD_PREFIX" == https://* ]] || exit 2
TOOL="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"
[[ -x "$TOOL" ]] || { echo 'Resolve Swift packages first.' >&2; exit 2; }
"$TOOL" --account hoyobridge-updates --maximum-deltas 0 \
  --download-url-prefix "$DOWNLOAD_PREFIX" "$RELEASE_DIR"
echo 'Appcast generated locally. Verify signatures and hosted download links before publishing.'
