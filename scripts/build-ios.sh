#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_dir="${1:-"$root/build"}"
mkdir -p "$output_dir"
sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
output="$output_dir/iris.dylib"

xcrun --sdk iphoneos clang \
  -target arm64-apple-ios15.0 \
  -isysroot "$sdk" -fobjc-arc -fblocks -fvisibility=hidden \
  -Wall -Wextra -dynamiclib -Wl,-install_name,@rpath/iris.dylib \
  -framework Foundation -framework CoreFoundation -framework UIKit -framework UniformTypeIdentifiers \
  "$root/Sources/IrisPreferences.m" "$root/Sources/IrisSettingsViewController.m" \
  "$root/Sources/IrisHeader.m" -o "$output"

test "$(xcrun lipo -archs "$output")" = arm64
xcrun otool -hv "$output" | grep -qw DYLIB
xcrun otool -D "$output" | grep -Fxq '@rpath/iris.dylib'
(cd "$output_dir" && shasum -a 256 iris.dylib > SHA256SUMS)
printf 'Built %s\n' "$output"
