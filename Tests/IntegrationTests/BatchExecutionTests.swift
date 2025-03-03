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

    @Suite final class BatchExecutionTests {
        private let client: OracleClient
        private var running: Task<Void, Error>!

        init() throws {
            let client = try OracleClient(configuration: OracleConnection.testConfig(), backgroundLogger: .oracleTest)
            self.client = client
            self.running = Task { await client.run() }
        }

        deinit {
            running.cancel()
        }

        @Test func simpleBatchExecution() async throws {
            try await client.withConnection { connection in
                do {
                    try await connection.execute("DROP TABLE users_simple_batch_exec", logger: .oracleTest)
                } catch let error as OracleSQLError {
                    // "ORA-00942: table or view does not exist" can be ignored
                    #expect(error.serverInfo?.number == 942)
                }
                try await connection.execute(
                    "CREATE TABLE users_simple_batch_exec (id NUMBER, name VARCHAR2(50 byte), age NUMBER)")
                let binds: [(Int, String, Int?)] = [
                    (1, "John", nil),
                    (2, "Jane", 30),
                    (3, "Jack", 40),
                    (4, "Jill", 50),
                    (5, "Pete", nil),
                ]
                let batchResult = try await connection.executeBatch(
                    "INSERT INTO users_simple_batch_exec (id, name, age) VALUES (:1, :2, :3)", binds: binds)
                #expect(batchResult.affectedRows == binds.count)
                let stream = try await connection.execute(
                    "SELECT id, name, age FROM users_simple_batch_exec ORDER BY id ASC")
                var index: Int = 0
                for try await (id, name, age) in stream.decode((Int, String, Int?).self) {
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

        @Test func preparedStatementBatchExecution() async throws {
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
                let batchResult = try await connection.executeBatch(binds)
                #expect(batchResult.affectedRows == binds.count)
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

        @Test func batchExecutionWithErrorDiscardsRemaining() async throws {
            struct InsertUserStatement: OraclePreparedStatement {
                static let sql: String =
                    "INSERT INTO users_error_discards_batch_exec (id, name, age) VALUES (:1, :2, :3)"

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

            try await client.withConnection { connection in
                do {
                    try await connection.execute("DROP TABLE users_error_discards_batch_exec", logger: .oracleTest)
                } catch let error as OracleSQLError {
                    // "ORA-00942: table or view does not exist" can be ignored
                    #expect(error.serverInfo?.number == 942)
                }
                try await connection.execute(
                    "CREATE TABLE users_error_discards_batch_exec (id NUMBER, name VARCHAR2(50 byte), age NUMBER)")
                let binds: [InsertUserStatement] = [
                    InsertUserStatement(id: 1, name: "John", age: 20),
                    InsertUserStatement(id: 2, name: "Jane", age: 30),
                    InsertUserStatement(
                        id: 3, name: "Jack's name is too long to fit into this column, so we fail here", age: 40),
                    InsertUserStatement(id: 4, name: "Jill", age: 50),
                    InsertUserStatement(id: 5, name: "Pete", age: 60),
                ]
                do {
                    try await connection.executeBatch(binds)
                } catch let error as OracleSQLError {
                    // expect a value too long for column error here
                    guard error.serverInfo?.number == 12899 else { throw error }
                    #expect(error.serverInfo?.affectedRows == 2)
                }
                let stream = try await connection.execute(
                    "SELECT id, name, age FROM users_error_discards_batch_exec ORDER BY id ASC")
                var index: Int = 0
                for try await (id, name, age) in stream.decode((Int, String, Int).self) {
                    guard index < 2 else {
                        Issue.record("Too many rows")
                        return
                    }
                    let expected = binds[index]
                    #expect(id == expected.id)
                    #expect(name == expected.name)
                    #expect(age == expected.age)
                    index += 1
                }
                #expect(index == 2)
            }
        }

        @Test func batchExecutionWithBatchErrorsDoesNotDiscardSuccess() async throws {
            struct InsertUserStatement: OraclePreparedStatement {
                static let sql: String =
                    "INSERT INTO users_batch_error_does_not_discard_batch_exec (id, name, age) VALUES (:1, :2, :3)"

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

            try await client.withConnection { connection in
                do {
                    try await connection.execute(
                        "DROP TABLE users_batch_error_does_not_discard_batch_exec", logger: .oracleTest)
                } catch let error as OracleSQLError {
                    // "ORA-00942: table or view does not exist" can be ignored
                    #expect(error.serverInfo?.number == 942)
                }
                try await connection.execute(
                    "CREATE TABLE users_batch_error_does_not_discard_batch_exec (id NUMBER, name VARCHAR2(50 byte), age NUMBER)"
                )
                var binds: [InsertUserStatement] = [
                    InsertUserStatement(id: 1, name: "John", age: 20),
                    InsertUserStatement(id: 2, name: "Jane", age: 30),
                    InsertUserStatement(
                        id: 3, name: "Jack's name is too long to fit into this column, so we fail here", age: 40),
                    InsertUserStatement(id: 4, name: "Jill", age: 50),
                    InsertUserStatement(id: 5, name: "Pete", age: 60),
                ]
                var options = StatementOptions()
                options.batchErrors = true
                options.arrayDMLRowCounts = true
                do {
                    try await connection.executeBatch(binds, options: options)
                } catch let error as OracleBatchExecutionError {
                    #expect(error.result.affectedRows == 4)
                    #expect(error.result.affectedRowsPerStatement == [1, 1, 0, 1, 1])
                    #expect(error.errors.first?.statementIndex == 2)
                    #expect(error.errors.first?.number == 12899)
                }
                let stream = try await connection.execute(
                    "SELECT id, name, age FROM users_batch_error_does_not_discard_batch_exec ORDER BY id ASC")
                var index: Int = 0
                binds.remove(at: 2)  // malformed data
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
    }
#endif
