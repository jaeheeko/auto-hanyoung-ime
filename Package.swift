// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "hanyoung",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "Engine", path: "Sources/Engine"),
        .executableTarget(
            name: "Hanyoung",
            dependencies: ["Engine"],
            path: "Sources/Hanyoung",
            exclude: ["Info.plist"],
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("InputMethodKit"),
            ]
        ),
        .testTarget(name: "EngineTests", dependencies: ["Engine"], path: "Tests/EngineTests"),
    ]
)
