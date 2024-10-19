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

import XCTest

@testable import OracleNIO

final class OracleClientTests: XCTestCase {

    func testPool() async throws {
        try XCTSkipIf(
            env("NO_DRCP") != nil, "The testing database does not support DRCP, skipping test...")
        let config = try OracleConnection.testConfig()
        let client = OracleClient(configuration: config, backgroundLogger: .oracleTest)
        await withThrowingTaskGroup(of: Void.self) { taskGroup in
            taskGroup.addTask {
                await client.run()
            }

            for i in 0..<10000 {
                taskGroup.addTask {
                    try await client.withConnection { connection in
                        do {
                            let rows = try await connection.execute(
                                "SELECT 1, 'Timo', 23 FROM dual", logger: .oracleTest)
                            for try await (userID, name, age) in rows.decode(
                                (Int, String, Int).self)
                            {
                                XCTAssertEqual(userID, 1)
                                XCTAssertEqual(name, "Timo")
                                XCTAssertEqual(age, 23)
                                print("done: \(i)/10000")
                            }
                        } catch {
                            XCTFail("Unexpected error: \(error)")
                        }
                    }
                }
            }

            for _ in 0..<10000 {
                _ = await taskGroup.nextResult()!
            }

            taskGroup.cancelAll()
        }
    }

    func testPoolWithoutDRCP() async throws {
        let config = try OracleConnection.testConfig()
        let client = OracleClient(configuration: config, drcp: false, backgroundLogger: .oracleTest)
        await withThrowingTaskGroup(of: Void.self) { taskGroup in
            taskGroup.addTask {
                await client.run()
            }

            for i in 0..<10000 {
                taskGroup.addTask {
                    try await client.withConnection { connection in
                        do {
                            let rows = try await connection.execute(
                                "SELECT 1, 'Timo', 23 FROM dual", logger: .oracleTest)
                            for try await (userID, name, age) in rows.decode(
                                (Int, String, Int).self)
                            {
                                XCTAssertEqual(userID, 1)
                                XCTAssertEqual(name, "Timo")
                                XCTAssertEqual(age, 23)
                                print("done: \(i)/10000")
                            }
                        } catch {
                            XCTFail("Unexpected error: \(error)")
                        }
                    }
                }
            }

            for _ in 0..<10000 {
                _ = await taskGroup.nextResult()!
            }

            taskGroup.cancelAll()
        }
    }

    func testTransactionSuccess() async throws {
        let config = try OracleConnection.testConfig()
        let client = OracleClient(configuration: config, drcp: false, backgroundLogger: .oracleTest)
        let runTask = Task {
            await client.run()
        }
        try await client.withTransaction { connection in
            _ = try? await connection.execute("DROP TABLE test_pool_transaction_success")
            try await connection.execute("CREATE TABLE test_pool_transaction_success (id NUMBER)")
            let affectedRows = try await connection.executeBatch(
                "INSERT INTO test_pool_transaction_success (id) VALUES (:1)",
                binds: Array(1...10)
            ).affectedRows
            XCTAssertEqual(affectedRows, 10)
        }
        try await client.withConnection { connection in
            let stream = try await connection.execute("SELECT id FROM test_pool_transaction_success")
            var index = 0
            for try await id in stream.decode(Int.self) {
                index += 1
                XCTAssertEqual(index, id)
            }
            XCTAssertEqual(index, 10)
        }
        runTask.cancel()
    }

    func testTransactionFailure() async throws {
        let config = try OracleConnection.testConfig()
        let client = OracleClient(configuration: config, drcp: false, backgroundLogger: .oracleTest)
        let runTask = Task {
            await client.run()
        }
        do {
            try await client.withTransaction { connection in
                _ = try? await connection.execute("DROP TABLE test_pool_transaction_failure")
                try await connection.execute("CREATE TABLE test_pool_transaction_failure (id VARCHAR2(1 byte))")
                try await connection.executeBatch(
                    "INSERT INTO test_pool_transaction_failure (id) VALUES (:1)",
                    binds: Array(1...10).map({ "\($0)" })
                )
            }
        } catch let error as OracleSQLError {
            XCTAssertEqual(error.serverInfo?.affectedRows, 9)
        }
        try await client.withConnection { connection in
            let rows =
                try await connection
                .execute("SELECT id FROM test_pool_transaction_failure")
                .collect()
                .count
            XCTAssertEqual(rows, 0)
        }
        runTask.cancel()
    }

    @available(macOS 14.0, *)
    func testPingPong() async throws {
        let idleTimeout = Duration.seconds(20)
        let config = try OracleConnection.testConfig()
        var options = OracleClient.Options()
        options.keepAliveBehavior?.frequency = .seconds(10)
        options.connectionIdleTimeout = idleTimeout
        let client = OracleClient(
            configuration: config, options: options, backgroundLogger: .oracleTest)

        let task = Task {
            await client.run()
        }

        try await withThrowingDiscardingTaskGroup { group in
            for _ in 0..<options.maximumConnections {
                group.addTask {
                    let hello = try await client.withConnection { db in
                        try await db.execute("SELECT 'hello' FROM dual", logger: .oracleTest)
                    }.collect().first?.decode(String.self)
                    XCTAssertEqual(hello, "hello")

                    // wait for the connection pool to do ping pong and close
                    try await Task.sleep(for: idleTimeout + .seconds(1))
                }
            }
        }

        task.cancel()
    }

}
