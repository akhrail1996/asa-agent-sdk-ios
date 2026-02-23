// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ASAAgentSDK",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(
            name: "ASAAgentSDK",
            targets: ["ASAAgentSDK"]
        ),
    ],
    targets: [
        .target(
            name: "ASAAgentSDK",
            path: "Sources/ASAAgentSDK"
        ),
        .testTarget(
            name: "ASAAgentSDKTests",
            dependencies: ["ASAAgentSDK"],
            path: "Tests/ASAAgentSDKTests"
        ),
    ]
)
