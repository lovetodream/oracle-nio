// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "OracleNIO",
    platforms: [.macOS(.v13)],
    products: [
        .library(
            name: "OracleNIO",
            targets: ["OracleNIO"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.46.0"),
        .package(url: "https://github.com/apple/swift-nio-transport-services.git", from: "1.13.1"),
        .package(url: "https://github.com/apple/swift-nio-extras.git", from: "1.15.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "2.2.4"),
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift.git", from: "1.6.0"),
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
                .product(name: "NIOTLS", package: "swift-nio"),
                .product(name: "NIOExtras", package: "swift-nio-extras"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "CryptoSwift", package: "CryptoSwift"),
            ]
        ),
        .executableTarget(name: "OracleNIOExample", dependencies: ["OracleNIO"]),
        .testTarget(
            name: "OracleNIOTests",
            dependencies: ["OracleNIO"]
        ),
    ]
)
