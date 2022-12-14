// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "oracle-nio",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .watchOS(.v6),
        .tvOS(.v13),
    ],
    products: [
        .library(
            name: "OracleNIO",
            targets: ["OracleNIO"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.0.0"),
    ],
    targets: [
        .target(name: "ODPIC"),
        .target(
            name: "OracleNIO",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(name: "NIO", package: "swift-nio"),
                "ODPIC",
            ]),
        .testTarget(
            name: "OracleNIOTests",
            dependencies: ["OracleNIO"]),
    ]
)
