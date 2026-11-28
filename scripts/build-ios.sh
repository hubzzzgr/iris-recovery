#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_dir="${1:-"$root/build"}"
mkdir -p "$output_dir"
sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
output="$output_dir/iris.dylib"
zstd_version=1.5.7
zstd_dir="${IRIS_ZSTD_DIR:-$output_dir/.deps/zstd-$zstd_version}"
if [[ ! -f "$zstd_dir/lib/zstd.h" && -z "${IRIS_ZSTD_DIR:-}" ]]; then
  dependency_dir="$output_dir/.deps"
  mkdir -p "$dependency_dir"
  archive="$dependency_dir/zstd-$zstd_version.tar.gz"
  curl --fail --location --silent --show-error \
    "https://github.com/meta/zstd/releases/download/v$zstd_version/zstd-$zstd_version.tar.gz" -o "$archive"
  printf '%s  %s\n' eb33e51f49a15e023950cd7825ca74a4a2b43db8354825ac24fc1b7ee09e6fa3 "$archive" | shasum -a 256 -c -
  tar -xzf "$archive" -C "$dependency_dir"
fi
test -f "$zstd_dir/lib/zstd.h"
zstd_sources=("$zstd_dir"/lib/{common,compress,decompress}/*.c)

xcrun --sdk iphoneos clang \
  -target arm64-apple-ios15.0 \
  -isysroot "$sdk" -fobjc-arc -fblocks -fvisibility=hidden -O2 \
  -DZSTD_DISABLE_ASM=1 -DZSTD_LEGACY_SUPPORT=0 -DZSTDLIB_VISIBLE= \
  -I "$zstd_dir/lib" -Wall -Wextra -dynamiclib -Wl,-install_name,@rpath/iris.dylib \
  -framework Foundation -framework CoreFoundation -framework CoreGraphics -framework CoreImage \
  -framework UIKit -framework UniformTypeIdentifiers -framework PhotosUI -framework Photos \
  -framework AVFoundation -framework QuartzCore \
  "$root/Sources/IrisPreferences.m" "$root/Sources/IrisSettingsViewController.m" \
  "$root/Sources/IrisHeader.m" "$root/Sources/IrisRefresh.m" "$root/Sources/IrisMediaViewController.m" \
  "${zstd_sources[@]}" -o "$output"

test "$(xcrun lipo -archs "$output")" = arm64
xcrun otool -hv "$output" | grep -qw DYLIB
xcrun otool -D "$output" | grep -Fxq '@rpath/iris.dylib'
cp "$zstd_dir/LICENSE" "$output_dir/Zstandard-LICENSE.txt"
(cd "$output_dir" && shasum -a 256 iris.dylib > SHA256SUMS)
printf 'Built %s\n' "$output"
