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
            try await connection.execute(
                """
                CREATE TABLE IF NOT EXISTS sample_numeric_table(intv number)
                """)
            try await connection.execute("TRUNCATE TABLE sample_numeric_table")
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
}
