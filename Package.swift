// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "swift-deslop",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "swift-deslop", targets: ["swift-deslop"]),
        .library(name: "DeslopModel", targets: ["DeslopModel"]),
        .library(name: "DeslopCore", targets: ["DeslopCore"]),
        .library(name: "DeslopSwift", targets: ["DeslopSwift"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "604.0.0"),
        .package(url: "https://github.com/1amageek/swift-testing-heartbeat.git", exact: "0.1.1"),
    ],
    targets: [
        .target(name: "DeslopModel"),
        .target(name: "DeslopCore", dependencies: ["DeslopModel"]),
        .target(name: "CIndexStore"),
        .target(
            name: "DeslopSwift",
            dependencies: [
                "DeslopModel",
                "CIndexStore",
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ]
        ),
        .executableTarget(
            name: "swift-deslop",
            dependencies: ["DeslopModel", "DeslopCore", "DeslopSwift"]
        ),
        .testTarget(name: "DeslopModelTests", dependencies: ["DeslopModel"]),
        .testTarget(name: "DeslopCoreTests", dependencies: ["DeslopModel", "DeslopCore"]),
        .testTarget(
            name: "DeslopSwiftTests",
            dependencies: [
                "DeslopModel", "DeslopCore", "DeslopSwift",
                .product(name: "TestHeartbeat", package: "swift-testing-heartbeat"),
            ]
        ),
        .testTarget(
            name: "DeslopTests",
            dependencies: [
                "swift-deslop", "DeslopModel",
                .product(name: "TestHeartbeat", package: "swift-testing-heartbeat"),
            ]
        ),
    ]
)
