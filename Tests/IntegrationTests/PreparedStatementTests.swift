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

#if compiler(>=6.0)
    import OracleNIO
    import OracleNIOMacros
    import Testing

    @Suite final class PreparedStatementTests {
        private let client: OracleClient
        private var running: Task<Void, Error>!

        init() throws {
            let client = try OracleClient(configuration: OracleConnection.testConfig())
            self.client = client
            self.running = Task { await client.run() }
        }

        deinit {
            running.cancel()
        }

        @Test func selectFromDual() async throws {
            try await self.client.withConnection { connection in
                let stream1 = try await connection.execute(SelectFromDualQuery())
                var stream1Count = 0
                for try await row in stream1 {
                    #expect(row.count == 1)
                    stream1Count += 1
                }
                #expect(stream1Count == 1)
                let stream2 = try await connection.execute(
                    SelectFromDualWithWhereClauseQuery(minCount: 1))
                var stream2Count = 0
                for try await row in stream2 {
                    #expect(row.count == 1)
                    stream2Count += 1
                }
                #expect(stream2Count == 1)
                let stream3 = try await connection.execute(SelectNullFromDualQuery())
                var stream3Count = 0
                for try await row in stream3 {
                    #expect(row.count == nil)
                    stream3Count += 1
                }
                #expect(stream3Count == 1)
                let stream4 = try await connection.execute(SelectAliasReservedNameWorksQuery())
                var stream4Count = 0
                for try await row in stream4 {
                    #expect(row.start == 1)
                    stream4Count += 1
                }
                #expect(stream4Count == 1)
                let stream5 = try await connection.execute(SelectAliasReservedNameMultilineWorksQuery())
                var stream5Count = 0
                for try await row in stream5 {
                    #expect(row.start == 1)
                    stream5Count += 1
                }
                #expect(stream5Count == 1)
            }
        }
    }

    @Statement("SELECT \("1", Int.self, as: "count") FROM dual")
    struct SelectFromDualQuery {}

    @Statement(
        "SELECT \("1", Int.self, as: "count") FROM dual WHERE 1 >= \(bind: "minCount", OracleNumber?.self)"
    )
    struct SelectFromDualWithWhereClauseQuery {}

    @Statement("SELECT \("NULL", Int?.self, as: "count") FROM dual")
    struct SelectNullFromDualQuery {}

    @Statement("SELECT \("1", Int.self, as: "start") FROM dual")
    struct SelectAliasReservedNameWorksQuery {}

    @Statement(
        """
        SELECT \("1", Int.self, as: "start") 
        FROM dual
        """)
    struct SelectAliasReservedNameMultilineWorksQuery {}
#endif
