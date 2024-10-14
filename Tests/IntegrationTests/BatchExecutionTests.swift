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
    import Testing

    @Suite
    final class BatchExecutionTests {
        private let client: OracleClient
        private var running: Task<Void, Error>!

        init() throws {
            self.client = try OracleClient(configuration: OracleConnection.testConfig())
            self.running = Task { await client.run() }
        }

        deinit {
            running.cancel()
        }

        @Test
        func simpleBatchExecution() async throws {
            try await client.withConnection { connection in
                do {
                    try await connection.execute("DROP TABLE users_simple_batch_exec", logger: .oracleTest)
                } catch let error as OracleSQLError {
                    // "ORA-00942: table or view does not exist" can be ignored
                    #expect(error.serverInfo?.number == 942)
                }
                try await connection.execute(
                    "CREATE TABLE users_simple_batch_exec (id NUMBER, name VARCHAR2(50 byte), age NUMBER)")
                let binds: [(Int, String, Int)] = [
                    (1, "John", 20),
                    (2, "Jane", 30),
                    (3, "Jack", 40),
                    (4, "Jill", 50),
                    (5, "Pete", 60),
                ]
                try await connection.executeBatch(
                    "INSERT INTO users_simple_batch_exec (id, name, age) VALUES (:1, :2, :3)", binds: binds)
                let stream = try await connection.execute(
                    "SELECT id, name, age FROM users_simple_batch_exec ORDER BY id ASC")
                var index: Int = 0
                for try await (id, name, age) in stream.decode((Int, String, Int).self) {
                    guard index < binds.count else {
                        Issue.record("Too many rows")
                        return
                    }
                    let expected = binds[index]
                    #expect(id == expected.0)
                    #expect(name == expected.1)
                    #expect(age == expected.2)
                    index += 1
                }
                #expect(index == binds.count)
            }
        }

        @Test
        func preparedStatementBatchExecution() async throws {
            try await client.withConnection { connection in
                do {
                    try await connection.execute("DROP TABLE users_prepared_statement_batch_exec", logger: .oracleTest)
                } catch let error as OracleSQLError {
                    // "ORA-00942: table or view does not exist" can be ignored
                    #expect(error.serverInfo?.number == 942)
                }
                try await connection.execute(
                    "CREATE TABLE users_prepared_statement_batch_exec (id NUMBER, name VARCHAR2(50 byte), age NUMBER)")
                let binds: [InsertUserStatement] = [
                    InsertUserStatement(id: 1, name: "John", age: 20),
                    InsertUserStatement(id: 2, name: "Jane", age: 30),
                    InsertUserStatement(id: 3, name: "Jack", age: 40),
                    InsertUserStatement(id: 4, name: "Jill", age: 50),
                    InsertUserStatement(id: 5, name: "Pete", age: 60),
                ]
                try await connection.executeBatch(binds)
                let stream = try await connection.execute(
                    "SELECT id, name, age FROM users_prepared_statement_batch_exec ORDER BY id ASC")
                var index: Int = 0
                for try await (id, name, age) in stream.decode((Int, String, Int).self) {
                    guard index < binds.count else {
                        Issue.record("Too many rows")
                        return
                    }
                    let expected = binds[index]
                    #expect(id == expected.id)
                    #expect(name == expected.name)
                    #expect(age == expected.age)
                    index += 1
                }
                #expect(index == binds.count)
            }
        }

        struct InsertUserStatement: OraclePreparedStatement {
            static let sql: String =
                "INSERT INTO users_prepared_statement_batch_exec (id, name, age) VALUES (:1, :2, :3)"

            typealias Row = Void

            var id: Int
            var name: String
            var age: Int

            func makeBindings() throws -> OracleBindings {
                var bindings = OracleBindings(capacity: 3)
                bindings.append(id)
                bindings.append(name)
                bindings.append(age)
                return bindings
            }

            func decodeRow(_ row: OracleRow) throws -> Row {}
        }
    }
#endif
