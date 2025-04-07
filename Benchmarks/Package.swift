// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Benchmarks",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/ordo-one/package-benchmark.git", from: "1.29.2"),
        .package(path: "../../oracle-nio"),
    ],
    targets: [
        .executableTarget(
            name: "OracleBench",
            dependencies: [
                .product(name: "Benchmark", package: "package-benchmark"),
                .product(name: "OracleNIO", package: "oracle-nio"),
                .product(name: "_OracleMockServer", package: "oracle-nio"),
            ],
            path: "Benchmarks/OracleBench",
            plugins: [
                .plugin(name: "BenchmarkPlugin", package: "package-benchmark")
            ]
        )
    ]
)
