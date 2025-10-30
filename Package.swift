// swift-tools-version: 6.1
// Copyright 2024 Timo Zacherl
// SPDX-License-Identifier: Apache-2.0

import CompilerPluginSupport
import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("MemberImportVisibility")
]

let package = Package(
    name: "oracle-nio",
    platforms: [.macOS(.v13), .iOS(.v16), .tvOS(.v16), .watchOS(.v9), .visionOS(.v1)],
    products: [
        .library(name: "OracleNIO", targets: ["OracleNIO"]),
        .library(name: "OracleNIOMacros", targets: ["OracleNIOMacros"]),
    ],
    traits: [
        .trait(name: "DistributedTracingSupport"),
        .default(enabledTraits: ["DistributedTracingSupport"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.4"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.81.0"),
        .package(url: "https://github.com/apple/swift-nio-transport-services.git", from: "1.23.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.29.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", "3.9.0"..<"5.0.0"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.3"),
        .package(url: "https://github.com/apple/swift-atomics.git", from: "1.2.0"),
        .package(url: "https://github.com/apple/swift-distributed-tracing.git", from: "1.3.0"),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "2.6.0"),
        .package(
            url: "https://github.com/swiftlang/swift-syntax.git",
            "601.0.0-latest"..."602.0.0-latest"),
    ],
    targets: [
        .target(
            name: "_OracleConnectionPoolModule",
            dependencies: [
                .product(name: "Atomics", package: "swift-atomics"),
                .product(name: "DequeModule", package: "swift-collections"),
            ],
            path: "Sources/OracleConnectionPoolModule",
            exclude: ["LICENSE"]
        ),
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
                .product(
                    name: "Tracing",
                    package: "swift-distributed-tracing",
                    condition: .when(traits: ["DistributedTracingSupport"])
                ),
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
                "_OracleConnectionPoolModule",
            ],
            swiftSettings: swiftSettings,
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
            dependencies: [
                .product(
                    name: "InMemoryTracing",
                    package: "swift-distributed-tracing",
                    condition: .when(traits: ["DistributedTracingSupport"])
                ),
                "OracleNIO", "OracleNIOMacros",
            ],
            resources: [.process("Data")]
        ),
        .target(
            name: "OracleMockServer",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOTransportServices", package: "swift-nio-transport-services"),
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "OracleMockServerTests",
            dependencies: ["OracleMockServer", "OracleNIO"]
        ),
        .target(
            name: "OracleNIOMacros",
            dependencies: ["OracleNIO", "OracleNIOMacrosPlugin"],
            swiftSettings: swiftSettings
        ),
        .macro(
            name: "OracleNIOMacrosPlugin",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "OracleNIOMacrosTests",
            dependencies: [
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
                "OracleNIOMacrosPlugin",
            ]
        ),
    ]
)

if Context.environment["ENABLE_ORACLE_BENCHMARKS"] != nil {
    package.platforms = [.macOS(.v14)]
    package.traits = [
        .trait(name: "DistributedTracingSupport"),
        .trait(name: "OracleBenchmarksEnabled"),
        .default(enabledTraits: ["DistributedTracingSupport", "OracleBenchmarksEnabled"]),
    ]
    package.dependencies.append(
        .package(url: "https://github.com/ordo-one/package-benchmark", from: "1.0.0")
    )
    package.targets.append(
        .executableTarget(
            name: "OracleBenchmarks",
            dependencies: [
                .product(name: "Benchmark", package: "package-benchmark"),
                "OracleMockServer", "OracleNIO",
            ],
            path: "Benchmarks/OracleBenchmarks",
            plugins: [
                .plugin(name: "BenchmarkPlugin", package: "package-benchmark")
            ]
        )
    )
}
