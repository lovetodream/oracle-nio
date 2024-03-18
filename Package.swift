// swift-tools-version: 5.9
// Copyright 2024 Timo Zacherl
// SPDX-License-Identifier: Apache-2.0

import PackageDescription

let package = Package(
    name: "oracle-nio",
    platforms: [.macOS(.v13), .iOS(.v16), .tvOS(.v16), .watchOS(.v9), .visionOS(.v1)],
    products: [
        .library(
            name: "OracleNIO",
            targets: ["OracleNIO"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.4.4"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.58.0"),
        .package(url: "https://github.com/apple/swift-nio-transport-services.git", from: "1.19.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.25.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.2.0"),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "2.4.1"),
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.20.2"),
    ],
    targets: [
        .target(name: "_PBKDF2", dependencies: [.product(name: "Crypto", package: "swift-crypto")]),
        .testTarget(name: "_PBKDF2Tests", dependencies: ["_PBKDF2"]),
        .target(
            name: "OracleNIO",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOTransportServices", package: "swift-nio-transport-services"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "NIOTLS", package: "swift-nio"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "_CryptoExtras", package: "swift-crypto"),
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
                .product(name: "_ConnectionPoolModule", package: "postgres-nio"),
                "_PBKDF2",
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency=complete"),
                .enableUpcomingFeature("BareSlashRegexLiterals"),
            ]
        ),
        .testTarget(
            name: "OracleNIOTests",
            dependencies: ["OracleNIO"],
            resources: [.process("Data")]
        ),
    ]
)
