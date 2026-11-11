// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SystemResourceViewer",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SystemResourceViewer", targets: ["SystemResourceViewer"])
    ],
    targets: [
        .executableTarget(
            name: "SystemResourceViewer",
            path: "Sources/SystemResourceViewer"
        ),
        .testTarget(
            name: "SystemResourceViewerTests",
            dependencies: ["SystemResourceViewer"]
        )
    ]
)
