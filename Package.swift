// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Lynx",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Lynx", targets: ["LynxApp"]),
        .executable(name: "lynx-opend-probe", targets: ["OpenDProbe"])
    ],
    targets: [
        .target(name: "LynxCore"),
        .executableTarget(name: "LynxApp", dependencies: ["LynxCore"]),
        .executableTarget(name: "OpenDProbe", dependencies: ["LynxCore"]),
        .testTarget(name: "LynxCoreTests", dependencies: ["LynxCore", "LynxApp"], resources: [.process("Fixtures")])
    ]
)
