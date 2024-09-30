// swift-tools-version: 5.9
// Copyright 2024 Timo Zacherl
// SPDX-License-Identifier: Apache-2.0

import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "oracle-nio",
    platforms: [.macOS(.v13), .iOS(.v16), .tvOS(.v16), .watchOS(.v9), .visionOS(.v1)],
    products: [
        .library(name: "OracleNIO", targets: ["OracleNIO"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.4"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.67.0"),
        .package(url: "https://github.com/apple/swift-nio-transport-services.git", from: "1.21.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.27.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.4.0"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.3"),
        .package(url: "https://github.com/apple/swift-atomics.git", from: "1.2.0"),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "2.6.0"),
        .package(
            url: "https://github.com/swiftlang/swift-syntax.git",
            "509.0.0-latest"..."600.0.0-latest"),
    ],
    targets: [
        .target(
            name: "_ConnectionPoolModule",
            dependencies: [
                .product(name: "Atomics", package: "swift-atomics"),
                .product(name: "DequeModule", package: "swift-collections"),
            ],
            path: "Sources/VendoredConnectionPoolModule"
        ),
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
                "_PBKDF2", "_ConnectionPoolModule", "OracleNIOMacros",
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency=complete"),
                .enableUpcomingFeature("BareSlashRegexLiterals"),
            ]
        ),
        .testTarget(
            name: "OracleNIOTests",
            dependencies: [
                "OracleNIO",
                .product(name: "NIOTestUtils", package: "swift-nio"),
            ]
        ),
        .testTarget(
            name: "IntegrationTests",
            dependencies: ["OracleNIO"],
            resources: [.process("Data")]
        ),
        .macro(
            name: "OracleNIOMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        .testTarget(
            name: "OracleNIOMacrosTests",
            dependencies: [
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
                "OracleNIOMacros",
            ]
        ),
    ]
)
