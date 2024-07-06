//===----------------------------------------------------------------------===//
//
// This source file is part of the OracleNIO open source project
//
// Copyright (c) 2024 Timo Zacherl and the OracleNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
// See CONTRIBUTORS.md for the list of OracleNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Benchmark
import Foundation
import OracleNIO

private func env(_ name: String) -> String? {
    getenv(name).flatMap { String(cString: $0) }
}

extension Benchmark {
    @discardableResult
    convenience init?(
        name: String,
        configuration: Benchmark.Configuration = Benchmark.defaultConfiguration,
        write: @escaping @Sendable (Benchmark, OracleConnection) async throws -> Void
    ) {
        let config = OracleConnection.Configuration(
            host: env("ORA_HOSTNAME") ?? "192.168.1.24",
            port: env("ORA_PORT").flatMap(Int.init) ?? 1521,
            service: .serviceName(env("ORA_SERVICE_NAME") ?? "XEPDB1"),
            username: env("ORA_USERNAME") ?? "my_user",
            password: env("ORA_PASSWORD") ?? "my_passwor"
        )
        var connection: OracleConnection!
        self.init(name, configuration: configuration) { benchmark in
            for _ in benchmark.scaledIterations {
                for _ in 0..<25 {
                    try await write(benchmark, connection)
                }
            }
        } setup: {
            connection = try await OracleConnection.connect(
                configuration: config,
                id: 1
            )
        } teardown: {
            try await connection.close()
        }
    }
}

let benchmarks = {
    Benchmark.defaultConfiguration = .init(
        metrics: [
            .cpuTotal,
            .contextSwitches,
            .throughput,
            .mallocCountTotal,
        ],
        warmupIterations: 10
    )
    Benchmark(
        name: "SELECT:DUAL:1",
        configuration: .init(warmupIterations: 10)
    ) { _, connection in
        let stream = try await connection.execute("SELECT 'hello' FROM dual")
        for try await _ in stream.decode(String.self) {}  // consume stream
    }

    Benchmark(
        name: "SELECT:DUAL:10_000",
        configuration: .init(warmupIterations: 10)
    ) { _, connection in
        let stream = try await connection.execute(
            "SELECT to_number(column_value) AS id FROM xmltable ('1 to 10000')"
        )
        for try await _ in stream.decode(Int.self) {}  // consume stream
    }
}
