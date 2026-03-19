// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "demos",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "demos",
            path: "Sources/demos",
            exclude: ["Info.plist"]
        )
    ]
)
