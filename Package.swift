// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "lookin-cli",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "lookin", targets: ["LookinCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "LookinCLI",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "LookinTransport",
            ],
        ),
        .target(
            name: "LookinTransport",
            dependencies: ["LookinCore"],
        ),
        .target(
            name: "LookinCore",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("."),
                .headerSearchPath(".."), // lets umbrella header find vendored headers in parent dir
                .define("LOOKIN_CLI_HOST", to: "1"),
                .define("SHOULD_COMPILE_LOOKIN_SERVER"),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
            ],
        ),
        .testTarget(name: "LookinTransportTests", dependencies: ["LookinTransport"]),
        .testTarget(name: "LookinCoreTests", dependencies: ["LookinCore"]),
        .testTarget(name: "LookinCLITests", dependencies: ["LookinCLI"]),
    ],
)
