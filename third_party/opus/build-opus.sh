#!/usr/bin/env bash
# Always use english in comments
set -euo pipefail

# Script location (expected at repo-root/third_party/opus/build-opus.sh)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# third_party/opus directory (this folder)
TP_OPUS_DIR="$SCRIPT_DIR"

# Repo root (two levels up from third_party/opus)
REPO_ROOT="$(cd "$TP_OPUS_DIR/../.." && pwd)"

# Find the latest "opus-*" source dir inside third_party/opus (e.g. opus-1.5.2)
OPUS_SRC_DIR="$(ls -d "$TP_OPUS_DIR"/opus-* 2>/dev/null | sort -V | tail -n1 || true)"
if [[ -z "${OPUS_SRC_DIR}" ]]; then
  echo "❌ Could not find sources like third_party/opus/opus-*/"
  exit 1
fi

# Build/output dirs live alongside the sources (kept inside third_party/opus)
BUILD_DIR="$TP_OPUS_DIR/build"
DIST_DIR="$TP_OPUS_DIR/dist"
HEADERS_DIR="$TP_OPUS_DIR/Headers"

# Final XCFramework goes to repo-root/vendor
OUT_DIR="$REPO_ROOT/vendor"
OUT_XC="$OUT_DIR/Opus.xcframework"

# Minimum OS versions (override by exporting IOS_MIN/WOS_MIN before running)
IOS_MIN="${IOS_MIN:-13.0}"
WOS_MIN="${WOS_MIN:-7.0}"
MAC_MIN="${MAC_MIN:-12.0}"
TV_MIN="${TV_MIN:-12.0}"

echo "▶ Using Opus sources: $OPUS_SRC_DIR"
echo "▶ Repo root:         $REPO_ROOT"
echo "▶ Output XCFramework: $OUT_XC"
echo "▶ iOS min: $IOS_MIN | watchOS min: $WOS_MIN"

rm -rf "$BUILD_DIR" "$DIST_DIR" "$HEADERS_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR" "$HEADERS_DIR" "$OUT_DIR"

# Copy public headers and add module map for Swift import
cp -R "$OPUS_SRC_DIR/include/"* "$HEADERS_DIR/"
cat > "$HEADERS_DIR/module.modulemap" <<'MMAP'
module Opus [system] {
  header "opus.h"
  header "opus_types.h"
  header "opus_defines.h"
  header "opus_multistream.h"
  export *
}
MMAP

build_one () {
  local PLATFORM="$1"      # iphoneos | iphonesimulator | watchos | watchsimulator
  local ARCH="$2"          # arm64 | arm64_32
  local MIN_FLAG="$3"      # -miphoneos-version-min=... | -mios-simulator-version-min=... | -mwatchos-version-min=... | -mwatchos-simulator-version-min=...
  local HOST="$4"          # arm-apple-darwin (sufficient for our targets)
  local EXTRA_CFG="$5"     # additional configure flags
  local OUT_NAME="$6"      # subfolder under $DIST_DIR

  local SDK; SDK="$(xcrun --sdk "$PLATFORM" --show-sdk-path)"
  local CC;  CC="$(xcrun --sdk "$PLATFORM" -f clang)"

  local BDIR="$BUILD_DIR/$OUT_NAME"
  rm -rf "$BDIR"; mkdir -p "$BDIR"
  pushd "$BDIR" >/dev/null

  export CC="$CC"
  export CFLAGS="-arch $ARCH $MIN_FLAG -isysroot $SDK -O3 -DNDEBUG"
  export LDFLAGS="-arch $ARCH -isysroot $SDK"

  # Configure for static lib only (no shared)
  "$OPUS_SRC_DIR/configure" \
    --host="$HOST" \
    --disable-shared \
    --enable-static \
    $EXTRA_CFG

  make -j"$(sysctl -n hw.ncpu)"
  mkdir -p "$DIST_DIR/$OUT_NAME"
  cp ./.libs/libopus.a "$DIST_DIR/$OUT_NAME/"

  popd >/dev/null
}

echo "▶ Building static libs …"

# =============================================================================
# DEVICE TARGETS (Physical Hardware)
# =============================================================================
# Device targets use single architectures because physical devices have fixed
# hardware architectures. Universal binaries are NOT needed for devices.

# iOS device (arm64 only)
# All supported iPhones use arm64 since iPhone 5s (2013). No universal binary needed.
build_one iphoneos          arm64    "-miphoneos-version-min=$IOS_MIN"             arm-apple-darwin "--disable-asm"      ios

# tvOS device (arm64 only)
# All Apple TVs use arm64 since 4th generation (2015). No universal binary needed.
build_one appletvos         arm64 "-mtvos-version-min=$TV_MIN"                     arm-apple-darwin "--disable-asm"      tvos

# watchOS device (REQUIRES UNIVERSAL: arm64_32 + arm64)
# This is the ONLY device target that needs a universal binary because:
# - Series 6 and earlier: arm64_32 architecture
# - Series 7 and newer: arm64 architecture
# Both architectures must be supported for device compatibility.
build_one watchos           arm64_32 "-mwatchos-version-min=$WOS_MIN"              arm-apple-darwin "--disable-asm"      watchos-arm64_32
build_one watchos           arm64    "-mwatchos-version-min=$WOS_MIN"              arm-apple-darwin "--disable-asm"      watchos-arm64

# =============================================================================
# SIMULATOR TARGETS (Run on Mac Hardware)
# =============================================================================
# Simulator targets ALWAYS need universal binaries because they run on Macs
# which can be either Intel (x86_64) or Apple Silicon (arm64).

# iOS simulator (universal: arm64 + x86_64)
build_one iphonesimulator   arm64    "-mios-simulator-version-min=$IOS_MIN"        arm-apple-darwin "--disable-asm"      ios-sim
build_one iphonesimulator   x86_64  "-mios-simulator-version-min=$IOS_MIN"        x86_64-apple-darwin "--disable-asm"   ios-sim-x86

# watchOS simulator (universal: arm64 + x86_64)
build_one watchsimulator    arm64    "-mwatchos-simulator-version-min=$WOS_MIN"    arm-apple-darwin "--disable-asm"      watchsim
build_one watchsimulator    x86_64  "-mwatchos-simulator-version-min=$WOS_MIN"    x86_64-apple-darwin "--disable-asm"   watchsim-x86

# tvOS simulator (universal: arm64 + x86_64)
build_one appletvsimulator  arm64 "-mtvos-simulator-version-min=$TV_MIN"           arm-apple-darwin "--disable-asm"      tvos-sim
build_one appletvsimulator  x86_64 "-mtvos-simulator-version-min=$TV_MIN"         x86_64-apple-darwin "--disable-asm"   tvos-sim-x86

# macOS (universal: arm64 + x86_64)
# macOS needs both architectures for Intel and Apple Silicon Macs
build_one macosx            arm64    "-mmacosx-version-min=$MAC_MIN"               aarch64-apple-darwin "--disable-asm"  macos
build_one macosx            x86_64  "-mmacosx-version-min=$MAC_MIN"               x86_64-apple-darwin "--disable-asm"   macos-x86

# =============================================================================
# UNIVERSAL BINARY CREATION
# =============================================================================
# Merge multiple architectures into universal/fat binaries where needed:
# - Simulators: ALWAYS need universal (Intel + Apple Silicon Mac support)
# - watchOS device: ONLY device target that needs universal (multi-generation support)
# - iOS/tvOS device: Do NOT need universal (single architecture per device)

merge_universal() {
  local out="$1"; shift
  local inputs=("$@")
  mkdir -p "$(dirname "$out")"
  # Keep only inputs that actually exist
  local existing=()
  for f in "${inputs[@]}"; do
    [[ -f "$f" ]] && existing+=("$f")
  done
  if [[ ${#existing[@]} -eq 0 ]]; then
    echo "❌ merge_universal: no inputs for $out" >&2
    exit 1
  elif [[ ${#existing[@]} -eq 1 ]]; then
    cp "${existing[0]}" "$out"
  else
    lipo -create "${existing[@]}" -output "$out"
  fi
}

# Create universal binaries by merging architectures
echo "▶ Creating universal binaries for multi-architecture targets..."

# Simulator universal binaries (needed for Mac compatibility)
merge_universal "$DIST_DIR/ios-sim-universal/libopus.a" \
  "$DIST_DIR/ios-sim/libopus.a" \
  "$DIST_DIR/ios-sim-x86/libopus.a"

merge_universal "$DIST_DIR/watchsim-universal/libopus.a" \
  "$DIST_DIR/watchsim/libopus.a" \
  "$DIST_DIR/watchsim-x86/libopus.a"

merge_universal "$DIST_DIR/tvos-sim-universal/libopus.a" \
  "$DIST_DIR/tvos-sim/libopus.a" \
  "$DIST_DIR/tvos-sim-x86/libopus.a"

# macOS universal binary (needed for Intel + Apple Silicon Macs)
merge_universal "$DIST_DIR/macos-universal/libopus.a" \
  "$DIST_DIR/macos/libopus.a" \
  "$DIST_DIR/macos-x86/libopus.a"

# watchOS DEVICE universal binary (needed for multi-generation watch support)
# This is the ONLY device platform that needs universal binary
merge_universal "$DIST_DIR/watchos-universal/libopus.a" \
  "$DIST_DIR/watchos-arm64_32/libopus.a" \
  "$DIST_DIR/watchos-arm64/libopus.a"

# Note: iOS and tvOS device targets remain single-architecture (arm64 only)

echo "▶ Creating XCFramework …"
rm -rf "$OUT_XC"
xcodebuild -create-xcframework \
  -library "$DIST_DIR/ios/libopus.a"                 -headers "$HEADERS_DIR" \
  -library "$DIST_DIR/ios-sim-universal/libopus.a"   -headers "$HEADERS_DIR" \
  -library "$DIST_DIR/watchos-universal/libopus.a"   -headers "$HEADERS_DIR" \
  -library "$DIST_DIR/watchsim-universal/libopus.a"  -headers "$HEADERS_DIR" \
  -library "$DIST_DIR/macos-universal/libopus.a"     -headers "$HEADERS_DIR" \
  -library "$DIST_DIR/tvos/libopus.a"                -headers "$HEADERS_DIR" \
  -library "$DIST_DIR/tvos-sim-universal/libopus.a"  -headers "$HEADERS_DIR" \
  -output "$OUT_XC"

echo "✅ Built $OUT_XC"
echo "   You can now link vendor/Opus.xcframework to your iOS and watchOS targets (Do Not Embed for static)."

# Optional: print quick arch summary
echo "▶ Summary:"
for f in "$DIST_DIR"/**/libopus.a; do
  echo " - $(basename "$(dirname "$f")") → $f"
  lipo -info "$f" || true
done
