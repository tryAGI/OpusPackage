# OpusPackage

Swift Package Manager wrapper for libopus on Apple platforms.

The package exposes:

- `OpusKit`: Swift encoder and decoder helpers.
- `OpusShims`: C shims for libopus control macros.
- `OpusTypes`: shared Swift codec configuration types.
- `Opus`: a prebuilt `Opus.xcframework` distributed as a GitHub release asset.

## Usage

```swift
.package(url: "https://github.com/tryAGI/OpusPackage", exact: "0.1.0")
```

## Rebuilding Opus.xcframework

Use the manual **Release XCFramework** GitHub Actions workflow for normal binary
refreshes. It rebuilds `vendor/Opus.xcframework`, zips the framework as the
archive root, computes the SwiftPM checksum, and publishes the release asset.

The vendored source and build script are kept under `third_party/opus/`.

```bash
bash third_party/opus/build-opus.sh
```

Release artifacts must be zipped with the XCFramework directory as the archive root:

```bash
ditto -c -k --sequesterRsrc --keepParent vendor/Opus.xcframework Opus.xcframework.zip
swift package compute-checksum Opus.xcframework.zip
```
