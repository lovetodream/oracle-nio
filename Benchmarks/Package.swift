// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Benchmarks",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/ordo-one/package-benchmark.git", from: "1.0.0"),
        .package(path: "../../oracle-nio"),
    ],
    targets: [
        .executableTarget(
            name: "OracleBench",
            dependencies: [
                .product(name: "Benchmark", package: "package-benchmark"),
                .product(name: "OracleNIO", package: "oracle-nio"),
            ],
            path: "Benchmarks/OracleBench",
            plugins: [
                .plugin(name: "BenchmarkPlugin", package: "package-benchmark")
            ]
        )
    ]
)
