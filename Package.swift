// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "demos",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "demos",
            path: "Sources/demos",
            exclude: ["Info.plist"],
            linkerSettings: [
                .linkedFramework("WidgetKit"),
                .linkedFramework("EventKit"),
                .linkedFramework("UserNotifications"),
                .linkedFramework("CoreWLAN"),
                .linkedLibrary("z")
            ]
        ),
        .executableTarget(
            name: "BackstageWidget",
            path: "Sources/BackstageWidget",
            exclude: ["Info.plist"],
            linkerSettings: [
                .linkedFramework("WidgetKit"),
                .linkedFramework("AppIntents")
            ]
        ),
        .executableTarget(
            name: "AbletonCrashAnalyzer",
            path: "Sources/AbletonCrashAnalyzer",
            exclude: ["Info.plist"]
        ),
        .testTarget(
            name: "demosTests",
            dependencies: ["demos"],
            path: "Tests/demosTests"
        )
    ]
)
