// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "VideoCompressor",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "VideoCompressor",
            path: "Sources/VideoCompressor"
        ),
        .testTarget(
            name: "VideoCompressorTests",
            dependencies: ["VideoCompressor"],
            path: "Tests/VideoCompressorTests"
        ),
    ]
)
