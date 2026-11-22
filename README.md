# OpusPackage

Swift Package Manager wrapper for libopus on Apple platforms.

The package exposes:

- `OpusKit`: Swift encoder and decoder helpers.
- `OpusShims`: C shims for libopus control macros.
- `OpusTypes`: shared Swift codec configuration types.
- `Opus`: a prebuilt `Opus.xcframework` distributed as a GitHub release asset.

## Usage

```swift
.package(url: "https://github.com/tryAGI/OpusPackage", exact: "0.1.3")
```

## Owned PCM decode output

`Opus.Decoder.decodePCM16(data:expected:into:)` decodes directly into a
caller-owned `Data` buffer without an intermediate PCM array. The returned
integer is the frame count per channel, and `Data.count` is trimmed to the
exact interleaved PCM16 byte length. A retained copy of the output stays
independent of subsequent decode calls through Data's copy-on-write storage.

`decodePCM16(data:fec:expected:into:)` also supports FEC recovery;
`concealPCM16(expected:into:)` generates PLC into the same owned output.
For preallocated native sample storage, use the overload accepting
`UnsafeMutableBufferPointer<opus_int16>`, whose length is checked before
calling libopus. Decoder instances remain stateful and must not be used
concurrently.

Version 0.1.3 adds Swift-only APIs and continues using the unchanged, checksum-
pinned v0.1.2 native XCFramework. No native binary rebuild is needed.

## Rebuilding Opus.xcframework

Use the manual **Release XCFramework** GitHub Actions workflow for normal binary
refreshes. It rebuilds `vendor/Opus.xcframework`, zips the framework as the
archive root, computes the SwiftPM checksum, and publishes the release asset.

The vendored source and build script are kept under `third_party/opus/`.
The binary XCFramework intentionally contains public headers without a generic
`module.modulemap`; `OpusShims` owns the Clang module boundary. This lets Xcode
link Opus alongside other static XCFrameworks that expose their own module map.

```bash
bash third_party/opus/build-opus.sh
```

Release artifacts must be zipped with the XCFramework directory as the archive root:

```bash
ditto -c -k --sequesterRsrc --keepParent vendor/Opus.xcframework Opus.xcframework.zip
swift package compute-checksum Opus.xcframework.zip
```
