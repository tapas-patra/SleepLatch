// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SleepLatch",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(
            name: "SleepLatch",
            targets: ["SleepLatch"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "SleepLatch"
        ),
    ],
    swiftLanguageModes: [.v6]
)
