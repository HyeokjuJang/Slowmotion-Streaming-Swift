// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SlowMotionCamera",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "SlowMotionCamera",
            targets: ["SlowMotionCamera"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/daltoniam/Starscream.git", from: "4.0.0")
    ],
    targets: [
        .target(
            name: "SlowMotionCamera",
            dependencies: ["Starscream"],
            path: "SlowMotionCamera"
        )
    ]
)
