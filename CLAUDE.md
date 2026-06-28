# CLAUDE.md - OpusPackage

This file provides guidance for the Opus codec Swift Package.

## Package Overview

- **Purpose:** Swift wrapper for native libopus codec
- **XCFramework:** GitHub release asset consumed by `Package.swift`

## Build Commands

```bash
# Build package
swift build

# Run tests
swift test
```

## XCFramework Management

### Rebuild XCFramework

When needed for new architectures or Swift versions:

```bash
bash third_party/opus/build-opus.sh
```

### Verify Architectures

```bash
# Check included architectures
plutil -p vendor/Opus.xcframework/Info.plist | grep -A10 -B5 SupportedArchitectures

# Verify specific binary
file vendor/Opus.xcframework/watchos-*/libopus.a

# Check for Opus symbols
nm vendor/Opus.xcframework/watchos-*/libopus.a | grep "_opus_encode"
```

### Architecture Requirements

| Platform | Required Architectures |
|----------|------------------------|
| **watchOS Simulator** | `arm64` + `x86_64` (universal) |
| **watchOS Device** | `arm64` (Series 7+) + `arm64_32` (Series 6 and earlier) |
| **iOS Simulator** | `arm64` + `x86_64` (universal) |
| **iOS Device** | `arm64` (single) |

## Swift 6.2+ Linking Issues

### Problem

After upgrading to Swift 6.2+, you may encounter undefined symbol errors for Opus functions (`_opus_decode`, `_opus_encode`, etc.) on physical watchOS devices.

### Root Cause

Swift 6.2 build system changes can cause cached artifacts to become incompatible. Newer Apple Watch models require `arm64` while older models use `arm64_32`.

### Solution

```bash
# 1. Clear all build caches
rm -rf ~/Library/Developer/Xcode/DerivedData/
rm -rf ~/Library/Caches/org.swift.swiftpm/
rm -rf .build/

# 2. Clean Xcode project
xcodebuild clean -project src/Advantage.xcodeproj -scheme "Advantage Watch App"

# 3. If issues persist, rebuild Opus XCFramework
bash third_party/opus/build-opus.sh

# 4. Test both simulator and device builds
xcodebuild -project src/Advantage.xcodeproj -scheme "Advantage Watch App" \
    -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm),OS=26.5' build
xcodebuild -project src/Advantage.xcodeproj -scheme "Advantage Watch App" \
    -destination 'id=DEVICE_ID' build
```

### Diagnosis Commands

```bash
# Check if architecture-related
xcodebuild -project src/Advantage.xcodeproj -scheme "Advantage Watch App" \
    -destination 'id=DEVICE_ID' build 2>&1 | grep -E "(Undefined symbol|opus_|Linker command failed|architecture)"

# Check device architecture
xcrun xctrace list devices | grep -A1 -B1 "Apple Watch"
```

## Cache Clearing Reference

```bash
# Xcode derived data
rm -rf ~/Library/Developer/Xcode/DerivedData/

# Swift Package Manager cache
rm -rf ~/Library/Caches/org.swift.swiftpm/

# Local package build artifacts
rm -rf src/OpusPackage/.build/
rm -rf src/AdvantageShared/.build/

# Clean Xcode project
xcodebuild clean -project src/Advantage.xcodeproj -scheme "Advantage"
xcodebuild clean -project src/Advantage.xcodeproj -scheme "Advantage Watch App"
```

## Physical Device Testing

**Essential test sequence after Opus-related changes:**

```bash
# 1. Test watchOS simulator (should always work)
xcodebuild -project src/Advantage.xcodeproj -scheme "Advantage Watch App" \
    -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm),OS=26.5' build

# 2. Test watchOS physical device (critical for Opus compatibility)
xcodebuild -project src/Advantage.xcodeproj -scheme "Advantage Watch App" \
    -destination 'id=DEVICE_ID' build

# 3. Test iOS builds
xcodebuild -project src/Advantage.xcodeproj -scheme "Advantage" \
    -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.5' build
```

**Note:** Always test physical device builds when making changes to the Opus XCFramework or updating Swift versions.

## Key Files

| File | Description |
|------|-------------|
| `Package.swift` | Package manifest |
| `Sources/OpusKit/` | Swift Opus codec implementation |
| `third_party/opus/` | Opus source and build scripts |

## Related Documentation

| Document | Description |
|----------|-------------|
| `README.md` | Package usage and release artifact notes |
| `third_party/opus/README.md` | Opus build details |
