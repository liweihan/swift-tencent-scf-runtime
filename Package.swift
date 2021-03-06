// swift-tools-version:5.2

import PackageDescription

let package = Package(
    name: "swift-tencent-scf-runtime",
    platforms: [
        .macOS(.v10_15),
    ],
    products: [
        // This library exports `TencentSCFRuntimeCore` and adds Foundation convenience methods.
        .library(name: "TencentSCFRuntime", targets: ["TencentSCFRuntime"]),
        // This has all the main functionality for SCF and it does not link Foundation.
        .library(name: "TencentSCFRuntimeCore", targets: ["TencentSCFRuntimeCore"]),
        // Common SCF events and Tencent Cloud helpers.
        .library(name: "TencentSCFEvents", targets: ["TencentSCFEvents"]),
        // Testing helpers and utilities.
        .library(name: "TencentSCFTesting", targets: ["TencentSCFTesting"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", .upToNextMajor(from: "2.17.0")),
        .package(url: "https://github.com/apple/swift-log.git", .upToNextMajor(from: "1.0.0")),
        .package(url: "https://github.com/swift-server/swift-backtrace.git", .upToNextMajor(from: "1.1.0")),
        .package(url: "https://github.com/stevapple/tencent-cloud-core.git", .upToNextMinor(from: "0.0.1"))
    ],
    targets: [
        .target(name: "TencentSCFRuntime", dependencies: [
            .byName(name: "TencentSCFRuntimeCore"),
            .product(name: "NIO", package: "swift-nio"),
            .product(name: "NIOFoundationCompat", package: "swift-nio"),
        ]),
        .testTarget(name: "TencentSCFRuntimeTests", dependencies: [
            .byName(name: "TencentSCFRuntimeCore"),
            .byName(name: "TencentSCFRuntime"),
        ]),
        .target(name: "TencentSCFRuntimeCore", dependencies: [
            .product(name: "TencentCloudCore", package: "tencent-cloud-core"),
            .product(name: "Logging", package: "swift-log"),
            .product(name: "Backtrace", package: "swift-backtrace"),
            .product(name: "NIOHTTP1", package: "swift-nio"),
        ]),
        .testTarget(name: "TencentSCFRuntimeCoreTests", dependencies: [
            .byName(name: "TencentSCFRuntimeCore"),
            .product(name: "NIOTestUtils", package: "swift-nio"),
            .product(name: "NIOFoundationCompat", package: "swift-nio"),
        ]),
        .target(name: "TencentSCFEvents", dependencies: []),
        .testTarget(name: "TencentSCFEventsTests", dependencies: ["TencentSCFEvents"]),
        // testing helper
        .target(name: "TencentSCFTesting", dependencies: [
            .byName(name: "TencentSCFRuntime"),
            .product(name: "NIO", package: "swift-nio"),
        ]),
        .testTarget(name: "TencentSCFTestingTests", dependencies: ["TencentSCFTesting"]),
        // for perf testing
        .target(name: "MockServer", dependencies: [
            .product(name: "NIOHTTP1", package: "swift-nio"),
        ]),
        .target(name: "StringSample", dependencies: ["TencentSCFRuntime"]),
        .target(name: "CodableSample", dependencies: ["TencentSCFRuntime"]),
    ]
)
