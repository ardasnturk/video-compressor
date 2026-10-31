// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "VideoCompressor",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.1"),
    ],
    targets: [
        .executableTarget(
            name: "VideoCompressor",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/VideoCompressor",
            linkerSettings: [
                // Sparkle.framework is copied into Contents/Frameworks by scripts/build-app.sh.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        .testTarget(
            name: "VideoCompressorTests",
            dependencies: ["VideoCompressor"],
            path: "Tests/VideoCompressorTests"
        ),
    ]
)
