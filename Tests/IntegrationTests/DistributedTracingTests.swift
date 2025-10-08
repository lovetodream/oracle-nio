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

#if DistributedTracingSupport
    import Testing
    import InMemoryTracing

    @testable import OracleNIO

    @Suite(.disabled(if: env("SMOKE_TEST_ONLY") == "1"), .timeLimit(.minutes(5))) final class DistributedTracingTests {
        private let tracer: InMemoryTracer
        private let config: OracleConnection.Configuration
        private let client: OracleClient
        private var running: Task<Void, Error>!

        init() throws {
            self.tracer = InMemoryTracer()
            var config = try OracleConnection.Configuration.test()
            config.tracing.tracer = self.tracer
            self.config = config
            let client = OracleClient(configuration: self.config)
            self.client = client
            self.running = Task { await client.run() }
        }

        deinit {
            self.running.cancel()
        }

        @Test func testExecuteSpan() async throws {
            let namespace = try await client.withConnection { connection in
                try await connection.execute("SELECT 1 FROM dual")
                return connection.databaseNamespace
            }
            #expect(tracer.finishedSpans.count == 1)
            let span = try #require(tracer.finishedSpans.first)
            #expect(span.operationName == "SELECT")
            #expect(span.kind == .client)
            #expect(
                span.attributes == [
                    "server.address": .string(self.config.host),
                    "server.port": .int64(Int64(self.config.port)),
                    "db.query.summary": "SELECT dual",
                    "db.query.text": "SELECT 1 FROM dual",
                    "db.namespace": .string(namespace),
                ])
            #expect(span.errors.isEmpty)
            #expect(span.status == nil)
        }

        @Test func testExecuteErrorSpan() async throws {
            let namespace = try await client.withConnection { connection in
                do {
                    _ = try await connection.execute("SELECT FROM dual")
                } catch let error as OracleSQLError {
                    #expect(error.code == .server)
                }
                return connection.databaseNamespace
            }
            #expect(tracer.finishedSpans.count == 1)
            let span = try #require(tracer.finishedSpans.first)
            #expect(span.operationName == "SELECT")
            #expect(span.kind == .client)
            #expect(
                span.attributes == [
                    "server.address": .string(self.config.host),
                    "server.port": .int64(Int64(self.config.port)),
                    "db.query.summary": "SELECT dual",
                    "db.query.text": "SELECT FROM dual",
                    "db.namespace": .string(namespace),
                    "error.type": "server",
                    "db.response.status_code": "ORA-00936",
                ])
            #expect(span.errors.count == 1)
            let error = try #require(span.errors.first)
            #expect((error.error as? OracleSQLError)?.code == .server)
            #expect(span.status?.code == .error)
        }
    }
#endif
