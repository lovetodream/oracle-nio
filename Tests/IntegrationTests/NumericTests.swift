//===----------------------------------------------------------------------===//
//
// This source file is part of the OracleNIO open source project
//
// Copyright (c) 2026 Timo Zacherl and the OracleNIO project authors
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

@Suite(.timeLimit(.minutes(5))) final class NumericTests {
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

    @Test func variousNumerics() async throws {
        try await client.withConnection { connection in
            _ = try? await connection.execute("DROP TABLE sample_numeric_table")
            try await connection.execute(
                """
                CREATE TABLE sample_numeric_table(intv number)
                """)
            let insertRows: [OracleNumber] = [
                OracleNumber(Int.min)
            ]
            for row in insertRows {
                try await connection.execute(
                    "INSERT INTO sample_numeric_table (intv) VALUES (\(row))"
                )
            }

            let stream = try await connection.execute(
                "SELECT intv FROM sample_numeric_table")
            var selectedRows: [Int] = []
            for try await row in stream.decode(Int.self) {
                selectedRows.append(row)
            }
            #expect(selectedRows.isEmpty == false)
            for index in insertRows.indices {
                #expect(Int(insertRows[index].doubleValue) == selectedRows[index])
            }
        }
    }

    @Test func negativeAndFractionalNumberRoundTrip() async throws {
        try await client.withConnection { connection in
            _ = try? await connection.execute("DROP TABLE sample_numeric_double_table")
            try await connection.execute(
                """
                CREATE TABLE sample_numeric_double_table(doublev number)
                """)
            let insertRows: [OracleNumber] = [
                OracleNumber(-24.42),
                OracleNumber(-1.0),
                OracleNumber(-100.0),
                OracleNumber(-0.000123),
                OracleNumber(-1e20),
                OracleNumber(-1.5e23),
                OracleNumber(-1e-5),
                OracleNumber(-5e-10),
                OracleNumber(-5e-9),
            ]
            for row in insertRows {
                try await connection.execute(
                    "INSERT INTO sample_numeric_double_table (doublev) VALUES (\(row))"
                )
            }

            let stream = try await connection.execute(
                "SELECT doublev FROM sample_numeric_double_table ORDER BY ROWID"
            )
            var selectedRows: [Double] = []
            for try await row in stream.decode(Double.self) {
                selectedRows.append(row)
            }
            #expect(selectedRows.count == insertRows.count)
            for index in insertRows.indices {
                #expect(insertRows[index].doubleValue == selectedRows[index])
            }
        }
    }

    @Test func negativeBinaryDoubleRoundTrip() async throws {
        try await client.withConnection { connection in
            _ = try? await connection.execute("DROP TABLE sample_binary_double_table")
            try await connection.execute(
                """
                CREATE TABLE sample_binary_double_table(doublev binary_double)
                """)
            let insertRows: [Double] = [
                -420.081500420, -1.0, -0.000123, -1e250, -1e-250,
            ]
            for row in insertRows {
                try await connection.execute(
                    "INSERT INTO sample_binary_double_table (doublev) VALUES (\(row))"
                )
            }

            let stream = try await connection.execute(
                "SELECT doublev FROM sample_binary_double_table ORDER BY ROWID"
            )
            var selectedRows: [Double] = []
            for try await row in stream.decode(Double.self) {
                selectedRows.append(row)
            }
            #expect(selectedRows == insertRows)
        }
    }
}
