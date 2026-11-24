// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RunQueue",
    targets: [
        .target(name: "RunQueue"),
        .testTarget(name: "RunQueueTests", dependencies: ["RunQueue"]),
    ]
)
