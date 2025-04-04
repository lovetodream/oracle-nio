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

@testable import OracleMockServer

@available(macOS 14.0, *)
@Test func connect() async throws {
    try await withThrowingDiscardingTaskGroup { group in
        group.addTask {
            do {
                try await OracleMockServer.run()
            } catch is CancellationError {
                print("cancelled")
            }
        }

        let connection = try await OracleConnection.connect(
            configuration: .init(
                host: "127.0.0.1",
                port: 6666,
                service: .serviceName("FREEPDB1"),
                username: "my_user",
                password: "my_passwor"
            ), id: 1)
        try await connection.close()

        group.cancelAll()
    }
}

@Test func select() async throws {
    try await withThrowingDiscardingTaskGroup { group in
        group.addTask {
            do {
                try await OracleMockServer.run()
            } catch is CancellationError {
                print("cancelled")
            }
        }

        let connection = try await OracleConnection.connect(
            configuration: .init(
                host: "127.0.0.1",
                port: 6666,
                service: .serviceName("FREEPDB1"),
                username: "my_user",
                password: "my_passwor"
            ), id: 1)
        let stream = try await connection.execute("SELECT 'hello' FROM dual")
        for try await _ in stream.decode(String.self) {}
        try await connection.close()

        group.cancelAll()
    }
}
