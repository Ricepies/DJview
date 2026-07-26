// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DJView",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "DJView", targets: ["DJView"])
    ],
    targets: [
        .target(
            name: "CDjVuBridge",
            path: "Sources/CDjVuBridge",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "DJView",
            dependencies: ["CDjVuBridge"],
            path: "Sources/DJView",
            linkerSettings: [
                .unsafeFlags([
                    "-L", "../djvu-bridge/target/release",
                    "-ldjvu_bridge"
                ])
            ]
        )
    ]
)
