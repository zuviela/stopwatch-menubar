// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Stopwatch",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Stopwatch",
            path: "Sources/Stopwatch"
        )
    ]
)
