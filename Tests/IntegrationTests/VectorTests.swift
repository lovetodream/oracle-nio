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

import OracleNIO
import Testing

@Suite(.enabled(if: env("TEST_VECTORS")?.isEmpty == false), .timeLimit(.minutes(5))) final class VectorTests {
    private let client: OracleClient
    private var running: Task<Void, Error>!

    init() throws {
        let client = try OracleClient(configuration: .test())
        self.client = client
        self.running = Task { await client.run() }
    }

    deinit {
        running.cancel()
    }

    @Test func basicVectorTable() async throws {
        try await client.withConnection { connection in
            try await connection.execute(
                """
                CREATE TABLE IF NOT EXISTS sample_vector_table(
                    v32 vector(3, float32),
                    v64 vector(3, float64),
                    v8  vector(3, int8),
                    vb  vector(24, binary)
                )
                """)
            try await connection.execute("TRUNCATE TABLE sample_vector_table")
            typealias Row = (
                OracleVectorFloat32?, OracleVectorFloat64, OracleVectorInt8, OracleVectorBinary
            )
            let insertRows: [Row] = [
                ([2.625, 2.5, 2.0], [22.25, 22.75, 22.5], [4, 5, 6], [13, 14, 15]),
                ([3.625, 3.5, 3.0], [33.25, 33.75, 33.5], [7, 8, 9], [21, 22, 23]),
                (nil, [15.75, 18.5, 9.25], [10, 11, 12], [29, 30, 31]),
            ]
            for row in insertRows {
                try await connection.execute(
                    "INSERT INTO sample_vector_table (v32, v64, v8, vb) VALUES (\(row.0), \(row.1), \(row.2), \(row.3))"
                )
            }

            let stream = try await connection.execute(
                "SELECT v32, v64, v8, vb FROM sample_vector_table")
            var selectedRows: [Row] = []
            for try await row in stream.decode(Row.self) {
                selectedRows.append(row)
            }
            #expect(selectedRows.isEmpty == false)
            for index in insertRows.indices {
                #expect(insertRows[index].0 == selectedRows[index].0)
                #expect(insertRows[index].1 == selectedRows[index].1)
                #expect(insertRows[index].2 == selectedRows[index].2)
                #expect(insertRows[index].3 == selectedRows[index].3)
            }
        }
    }

    @Test func flexibleVector() async throws {
        try await client.withConnection { connection in
            try await connection.execute(
                """
                CREATE TABLE IF NOT EXISTS sample_vector_table2(
                    v32 vector(*, float32)
                )
                """)
            try await connection.execute("TRUNCATE TABLE sample_vector_table2")
            let vector: OracleVectorFloat32 = [1.1, 2.2, 3.3, 4.4, 5.5]
            try await connection.execute(
                "INSERT INTO sample_vector_table2 (v32) VALUES (\(vector))"
            )

            let stream = try await connection.execute("SELECT v32 FROM sample_vector_table2")
            var selectedRows: [OracleVectorFloat32] = []
            for try await row in stream.decode(OracleVectorFloat32.self) {
                selectedRows.append(row)
            }
            #expect(selectedRows.count == 1)
            #expect(selectedRows[0] == vector)
        }
    }
}
