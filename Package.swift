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
        // Dependencies are now managed via CocoaPods
    ],
    targets: [
        .target(
            name: "SlowMotionCamera",
            dependencies: [],
            path: "SlowMotionCamera"
        )
    ]
)
