// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "OpusPackage",
    platforms: [
        .iOS("26.1"),
        .watchOS("26.1"),
        .macOS("26.1"),
    ],
    products: [
        .library(name: "OpusShims", targets: ["OpusShims"]),
        .library(name: "OpusKit", targets: ["OpusKit"]),
    ],
    targets: [
        .binaryTarget(
            name: "Opus",
            url: "https://github.com/tryAGI/OpusPackage/releases/download/v0.1.0/Opus.xcframework.zip",
            checksum: "f9e2edcfa3bc223de244d917ae96812879ad47ef05e8a37f31c11f11097d22e6"
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
            dependencies: ["Opus", "OpusShims", "OpusKit"],
            resources: [.process("Resources")]
        ),
    ]
)
