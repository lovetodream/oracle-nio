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

@Suite(.serialized, .timeLimit(.minutes(5))) struct ServerTests {
    @available(macOS 14.0, *)
    func runWithServer(_ body: (OracleConnection) async throws -> Void) async throws {
        var server: Task<Void, Error>!

        let _: Void = await withCheckedContinuation { continuation in
            server = Task {
                do {
                    try await OracleMockServer.run(continuation: continuation)
                } catch {
                    print(error)
                }
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
        try await body(connection)
        try await connection.close()

        server.cancel()
    }

    @available(macOS 14.0, *)
    @Test func connect() async throws {
        try await runWithServer { _ in }
    }

    @available(macOS 14.0, *)
    @Test func selectOne() async throws {
        try await runWithServer { connection in
            let stream = try await connection.execute("SELECT 'hello' FROM dual")
            var rows = 0
            for try await value in stream.decode(String.self) {
                rows += 1
                #expect(value == "hello")
            }
            #expect(rows == 1)
        }
    }

    @available(macOS 14.0, *)
    @Test func selectMany() async throws {
        try await runWithServer { connection in
            let stream = try await connection.execute(
                "SELECT to_number(column_value) AS id FROM xmltable ('1 to 10000')")
            var current = 0
            for try await value in stream.decode(Int.self) {
                current += 1
                #expect(current == value)
            }
            #expect(current == 10_000)
        }
    }
}
