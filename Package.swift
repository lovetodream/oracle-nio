// swift-tools-version: 5.8
import PackageDescription

let package = Package(
    name: "oracle-nio",
    platforms: [.macOS(.v13), .iOS(.v16), .tvOS(.v16), .watchOS(.v9)],
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
        .package(url: "https://github.com/apple/swift-crypto.git", from: "2.2.4"),
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift.git", from: "1.6.0"),
        .package(url: "https://github.com/vapor/postgres-nio.git", exact: "1.20.0"), // has to be updated explicitly to avoid source breaking changes, as `_ConnectionPoolModule` is not guaranteed to be stable across versions
    ],
    targets: [
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
                .product(name: "CryptoSwift", package: "CryptoSwift"),
                .product(name: "_ConnectionPoolModule", package: "postgres-nio"),
            ]
        ),
        .testTarget(
            name: "OracleNIOTests",
            dependencies: ["OracleNIO"],
            resources: [.process("Data")]
        ),
    ]
)
