// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "OpusPackage",
    platforms: [
        .iOS("26.1"),
        .watchOS("26.0"),
        .macOS("26.1"),
    ],
    products: [
        .library(name: "OpusShims", targets: ["OpusShims"]),
        .library(name: "OpusKit", targets: ["OpusKit"]),
    ],
    targets: [
        .binaryTarget(
            name: "Opus",
            url: "https://github.com/tryAGI/OpusPackage/releases/download/v0.1.2/Opus.xcframework.zip",
            checksum: "786b148365058fe0f07da92a69d679e1ed0afa0fc12e4ac0b3993a9f8c65adc8"
        ),
        // pure Swift types/helpers
        .target(name: "OpusTypes"),
        // C wrappers exposing CTL macros to Swift
        .target(
            name: "OpusShims",
            dependencies: ["Opus"],
            publicHeadersPath: ".", // exposes opus_shim.h to Swift
            cSettings: [
                // Ensure Clang modules are on; usually enabled by default
                .unsafeFlags(["-fmodules"]),
            ]
        ),
        // Optional: small Swift convenience API
        .target(
            name: "OpusKit",
            dependencies: ["Opus", "OpusShims", "OpusTypes"]
        ),
        // ✅ iOS unit tests (run via Xcode/xcodebuild on iOS Simulator)
        .testTarget(
            name: "OpusPackageTests",
            dependencies: ["OpusShims", "OpusKit"],
            resources: [.process("Resources")]
        ),
    ]
)
