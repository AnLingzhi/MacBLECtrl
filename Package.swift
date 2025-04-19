// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "MacBLECtrl",
    platforms: [.macOS(.v10_15)],
    dependencies: [
    .package(url: "https://github.com/vapor/vapor.git", from: "4.83.1")
],
    targets: [
        .target(
            name: "MacBLECtrl",
            dependencies: [
                .product(name: "Vapor", package: "vapor")
            ],
            resources: [.process("Sources/MacBLECtrl/Info.plist")]
        ),
        .testTarget(
            name: "MacBLECtrlTests",
            dependencies: ["MacBLECtrl"]
        )
    ]
)