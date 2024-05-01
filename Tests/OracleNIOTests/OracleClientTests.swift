//===----------------------------------------------------------------------===//
//
// This source file is part of the OracleNIO open source project
//
// Copyright (c) 2024 Timo Zacherl and the OracleNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
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
                            let rows = try await connection.query(
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
                            let rows = try await connection.query(
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

}
