//===----------------------------------------------------------------------===//
//
// This source file is part of the OracleNIO open source project
//
// Copyright (c) 2025 Timo Zacherl and the OracleNIO project authors
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

@Suite(.timeLimit(.minutes(5))) final class TransactionTests {
    private let client: OracleClient
    private var running: Task<Void, Error>!

    init() throws {
        let client = try OracleClient(configuration: .test())
        self.client = client
        self.running = Task { await client.run() }
    }

    deinit {
        self.running.cancel()
    }

    @Test func commit() async throws {
        try await client.withConnection { conn1 in
            do {
                try await conn1.execute(
                    "DROP TABLE test_commit", logger: .oracleTest
                )
            } catch let error as OracleSQLError {
                // "ORA-00942: table or view does not exist" can be ignored
                #expect(error.serverInfo?.number == 942)
            }
            try await conn1.execute(
                "CREATE TABLE test_commit (id number, title varchar2(150 byte))",
                logger: .oracleTest
            )
            try await conn1.execute(
                "INSERT INTO test_commit (id, title) VALUES (1, 'hello!')",
                logger: .oracleTest
            )
            let rows = try await conn1.execute(
                "SELECT id, title FROM test_commit ORDER BY id", logger: .oracleTest
            )
            var index = 0
            for try await row in rows.decode((Int, String).self) {
                #expect(index + 1 == row.0)
                index = row.0
                #expect(row.1 == "hello!")
            }

            try await client.withConnection { conn2 in
                let rowCountOnConn2BeforeCommit = try await conn2.execute(
                    "SELECT id, title FROM test_commit ORDER BY id", logger: .oracleTest
                ).collect().count
                #expect(rowCountOnConn2BeforeCommit == 0)

                try await conn1.commit()

                let rowsFromConn2AfterCommit = try await conn2.execute(
                    "SELECT id, title FROM test_commit ORDER BY id", logger: .oracleTest
                )
                index = 0
                for try await row
                        in rowsFromConn2AfterCommit
                    .decode((Int, String).self)
                {
                    #expect(index + 1 == row.0)
                    index = row.0
                    #expect(row.1 == "hello!")
                }
            }

            try await conn1.execute("DROP TABLE test_commit", logger: .oracleTest)
        }
    }

    @Test func rollback() async throws {
        try await client.withConnection { conn in
            do {
                try await conn.execute(
                    "DROP TABLE test_rollback", logger: .oracleTest
                )
            } catch let error as OracleSQLError {
                // "ORA-00942: table or view does not exist" can be ignored
                #expect(error.serverInfo?.number == 942)
            }
            try await conn.execute(
                "CREATE TABLE test_rollback (id number, title varchar2(150 byte))",
                logger: .oracleTest
            )
            try await conn.execute(
                "INSERT INTO test_rollback (id, title) VALUES (1, 'hello!')",
                logger: .oracleTest
            )
            let rows = try await conn.execute(
                "SELECT id, title FROM test_rollback ORDER BY id", logger: .oracleTest
            )
            var index = 0
            for try await row in rows.decode((Int, String).self) {
                #expect(index + 1 == row.0)
                index = row.0
                #expect(row.1 == "hello!")
            }

            try await conn.rollback()

            let rowCountAfterCommit = try await conn.execute(
                "SELECT id, title FROM test_rollback ORDER BY id", logger: .oracleTest
            ).collect().count
            #expect(rowCountAfterCommit == 0)

            try await conn.execute("DROP TABLE test_rollback", logger: .oracleTest)
        }
    }
}
