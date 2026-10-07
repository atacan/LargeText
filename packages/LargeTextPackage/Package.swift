// swift-tools-version: 6.0
import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ApproachableConcurrency"),
]

let package = Package(
    name: "LargeText",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LargeTextKit", targets: ["LargeTextKit"]),
    ],
    targets: [
        .target(name: "LargeTextCore", swiftSettings: swiftSettings),
        .target(name: "LargeTextPlatform", dependencies: ["LargeTextCore"], swiftSettings: swiftSettings),
        .target(name: "LargeTextUI", dependencies: ["LargeTextCore"], swiftSettings: swiftSettings),
        .target(
            name: "LargeTextKit",
            dependencies: ["LargeTextCore", "LargeTextPlatform", "LargeTextUI"],
            swiftSettings: swiftSettings
        ),
        // Plain library; must not import Testing. Test-only consumers, never shipped.
        .target(
            name: "LargeTextTestSupport",
            dependencies: ["LargeTextCore"],
            path: "Tests/LargeTextTestSupport",
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "LargeTextCoreTests",
            dependencies: ["LargeTextCore", "LargeTextTestSupport"],
            swiftSettings: swiftSettings
        ),
        .testTarget(name: "LargeTextPlatformTests", dependencies: ["LargeTextPlatform"], swiftSettings: swiftSettings),
        .testTarget(name: "LargeTextUITests", dependencies: ["LargeTextUI"], swiftSettings: swiftSettings),
        .testTarget(
            name: "LargeTextKitTests",
            dependencies: ["LargeTextKit", "LargeTextCore", "LargeTextTestSupport"],
            swiftSettings: swiftSettings
        ),
    ]
)
