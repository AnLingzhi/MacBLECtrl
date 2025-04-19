// swift-tools-version:5.8
import PackageDescription

let package = Package(
    name: "MacBLECtrl",
    platforms: [.macOS(.v10_15)],
    dependencies: [
    .package(url: "https://github.com/vapor/vapor.git", from: "4.83.1")
],
    targets: [
        .executableTarget( // Changed from .target to .executableTarget
            name: "MacBLECtrl",
            dependencies: [
                .product(name: "Vapor", package: "vapor")
            ],
            exclude: ["Info.plist"] // Explicitly exclude Info.plist to silence the warning
        ),
        .testTarget(
            name: "MacBLECtrlTests",
            dependencies: ["MacBLECtrl"]
        )
    ]
)
