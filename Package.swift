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
            ]
            // 移除Info.plist资源配置，因为它不支持作为顶级资源文件
        ),
        .testTarget(
            name: "MacBLECtrlTests",
            dependencies: ["MacBLECtrl"]
        )
    ]
)