#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
output_dir="$project_dir/LocalRuntimes/Experiments/native-window-adapter"
mkdir -p "$output_dir"
xcrun clang -fobjc-arc -fmodules -Wall -Wextra -Werror -framework AppKit \
  "$project_dir/script/native-window/geometry-test.m" -o "$output_dir/geometry-test"
"$output_dir/geometry-test"
xcrun clang -dynamiclib -fobjc-arc -fmodules -Wall -Wextra -Werror \
  -arch arm64 -arch x86_64 -mmacosx-version-min=15.0 -framework AppKit \
  "$project_dir/script/native-window/MGBWindowAdapter.m" -o "$output_dir/libMGBWindowAdapter.dylib"
codesign --force --sign - "$output_dir/libMGBWindowAdapter.dylib"
codesign --verify --strict "$output_dir/libMGBWindowAdapter.dylib"
mingw_cc="$project_dir/LocalRuntimes/Tools/llvm-mingw-20260616/bin/x86_64-w64-mingw32-gcc"
if [[ ! -x "$mingw_cc" ]]; then
  echo "Missing pinned llvm-mingw compiler: $mingw_cc" >&2
  exit 1
fi
"$mingw_cc" -Wall -Wextra -Werror -municode \
  "$project_dir/script/native-window/window-flags.c" -luser32 -o "$output_dir/window-flags.exe"
