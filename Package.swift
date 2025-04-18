// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "MacBLECtrl",
    platforms: [.macOS(.v10_15)],
    dependencies: [],
    targets: [
        .target(
            name: "MacBLECtrl",
            dependencies: []),
        .testTarget(
            name: "MacBLECtrlTests",
            dependencies: ["MacBLECtrl"]),
    ]
)