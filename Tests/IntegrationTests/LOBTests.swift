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

import Atomics
import Foundation
import Logging
import NIOCore
import OracleNIO
import Testing

@Suite(.disabled(if: env("SMOKE_TEST_ONLY") == "1"), .timeLimit(.minutes(5))) final class LOBTests {
    let fileURL: URL!
    let connection: OracleConnection

    private static let counter = ManagedAtomic(0)

    init() async throws {
        #expect(isLoggingConfigured)
        self.connection = try await OracleConnection.test()

        let filePath = try #require(
            Bundle.module.path(
                forResource: "Isaac_Newton-Opticks", ofType: "txt"
            ))
        self.fileURL = URL(fileURLWithPath: filePath)
    }

    deinit {
        #expect(throws: Never.self, performing: { try self.connection.syncClose() })
    }

    func runPopulatedTest<R>(_ test: @escaping (OracleConnection, String) async throws -> R) async throws {
        let key = String(Self.counter.wrappingIncrementThenLoad(ordering: .relaxed))
        do {
            try await connection.execute(
                "DROP TABLE test_simple_blob_\(unescaped: key)", logger: .oracleTest
            )
        } catch let error as OracleSQLError {
            // "ORA-00942: table or view does not exist" can be ignored
            #expect(error.serverInfo?.number == 942)
        }

        try await connection.execute(
            "CREATE TABLE test_simple_blob_\(unescaped: key) (id number, content blob)",
            logger: .oracleTest
        )

        await #expect(
            throws: Never.self,
            performing: {
                try await test(self.connection, "test_simple_blob_\(key)")
            })

        try await connection.execute(
            "DROP TABLE test_simple_blob_\(unescaped: key)", logger: .oracleTest
        )
    }

    @Test func simpleBinaryLOBViaData() async throws {
        let data = try Data(contentsOf: fileURL)

        try await runPopulatedTest { connection, tableName in
            try await connection.execute(
                "INSERT INTO \(unescaped: tableName) (id, content) VALUES (1, \(data))",
                logger: .oracleTest
            )
            let rows = try await connection.execute(
                "SELECT id, content FROM \(unescaped: tableName) ORDER BY id",
                logger: .oracleTest
            )
            var index = 0
            for try await row in rows.decode((Int, Data).self) {
                #expect(index + 1 == row.0)
                index = row.0
                #expect(row.1 == data)
                #expect(String(decoding: row.1, as: UTF8.self) == String(decoding: data, as: UTF8.self))
            }
        }
    }

    @Test func simpleBinaryLOBViaByteBuffer() async throws {
        let data = try Data(contentsOf: fileURL)
        let buffer = ByteBuffer(bytes: Array(data))

        try await runPopulatedTest { connection, tableName in
            try await connection.execute(
                "INSERT INTO \(unescaped: tableName) (id, content) VALUES (1, \(buffer))",
                logger: .oracleTest
            )
            try await self.validateLOB(expected: buffer, tableName: tableName, on: connection)
        }
    }

    @Test func simpleBinaryLOBViaLOB() async throws {
        let data = try Data(contentsOf: fileURL)
        let buffer = ByteBuffer(bytes: Array(data))

        try await runPopulatedTest { connection, tableName in
            try await connection.execute(
                "INSERT INTO \(unescaped: tableName) (id, content) VALUES (1, \(buffer))",
                logger: .oracleTest
            )
            func fetchLOB(chunkSize: Int?) async throws {
                var queryOptions = StatementOptions()
                queryOptions.fetchLOBs = true
                let rows = try await connection.execute(
                    "SELECT id, content FROM \(unescaped: tableName) ORDER BY id",
                    options: queryOptions,
                    logger: .oracleTest
                )
                var index = 0
                for try await (id, lob) in rows.decode((Int, LOB).self) {
                    #expect(lob.estimatedSize == buffer.readableBytes)
                    #expect(lob.estimatedChunkSize > 0)
                    index += 1
                    #expect(index == id)
                    var out = ByteBuffer()
                    for try await var chunk in lob.readChunks(ofSize: chunkSize, on: connection) {
                        out.writeBuffer(&chunk)
                    }
                    #expect(out == buffer)
                    #expect(
                        out.getString(at: 0, length: out.readableBytes)
                            == buffer.getString(at: 0, length: buffer.readableBytes)
                    )
                }
            }
            try await fetchLOB(chunkSize: nil)  // test with default chunk size
            try await fetchLOB(chunkSize: 4_294_967_295)  // test with huge chunk size
        }
    }

    @Test func writeLOBStream() async throws {
        let data = try Data(contentsOf: fileURL)
        var buffer = ByteBuffer(bytes: Array(data))
        let lobRef = OracleRef(dataType: .blob, isReturnBind: true)

        try await runPopulatedTest { connection, tableName in
            try await connection.execute(
                "INSERT INTO \(unescaped: tableName) (id, content) VALUES (1, empty_blob()) RETURNING content INTO \(lobRef)",
                options: .init(fetchLOBs: true)
            )
            let lob = try lobRef.decode(as: LOB.self)
            var offset = 1
            let chunkSize = 65536
            while buffer.readableBytes > 0,
                let slice =
                    buffer
                    .readSlice(length: min(chunkSize, buffer.readableBytes))
            {
                try await lob.write(slice, at: offset, on: connection)
                let newSize = try await lob.size(on: connection)
                offset += slice.readableBytes
                #expect(newSize == offset - 1)
            }
            // fast size does not update
            #expect(lob.estimatedSize == 0)
            buffer.moveReaderIndex(to: 0)
            try await self.validateLOB(expected: buffer, tableName: tableName, on: connection)
        }
    }

    @Test func writeLOBStreamWithExplicitOpenAndClose() async throws {
        let data = try Data(contentsOf: fileURL)
        var buffer = ByteBuffer(bytes: Array(data))
        let lobRef = OracleRef(dataType: .blob, isReturnBind: true)

        try await runPopulatedTest { connection, tableName in
            try await connection.execute(
                "INSERT INTO \(unescaped: tableName) (id, content) VALUES (1, empty_blob()) RETURNING content INTO \(lobRef)",
                options: .init(fetchLOBs: true)
            )
            let lob = try lobRef.decode(as: LOB.self)
            var offset = 1
            let chunkSize = 65536
            try await lob.open(on: connection)
            while buffer.readableBytes > 0,
                let slice =
                    buffer
                    .readSlice(length: min(chunkSize, buffer.readableBytes))
            {
                try await lob.write(slice, at: offset, on: connection)
                offset += slice.readableBytes
            }
            let isOpen = try await lob.isOpen(on: connection)
            #expect(isOpen)
            if isOpen {
                try await lob.close(on: connection)
            }
            buffer.moveReaderIndex(to: 0)
            try await self.validateLOB(expected: buffer, tableName: tableName, on: connection)
        }
    }

    @Test func temporaryLOB() async throws {
        try await runPopulatedTest { connection, tableName in
            let lob = try await LOB.create(.blob, on: connection)
            #expect(lob.estimatedChunkSize == 8060)  // the default
            let chunkSize = try await lob.chunkSize(on: connection)
            let buffer = ByteBuffer(bytes: [0x1, 0x2, 0x3, 0x4])
            try await lob.write(buffer, on: connection)
            try await connection.execute(
                "INSERT INTO \(unescaped: tableName) (id, content) VALUES (1, \(lob))"
            )
            #expect(chunkSize > 0)
            try await lob.free(on: connection)
            let optionalBuffer = try await connection.execute(
                "SELECT content FROM \(unescaped: tableName) WHERE id = 1"
            ).collect().first?.decode(ByteBuffer.self)
            #expect(buffer == optionalBuffer)
        }
    }

    @Test func createLOBFromUnsupportedDataType() async throws {
        await #expect(
            performing: {
                _ = try await LOB.create(.varchar, on: self.connection)
            },
            throws: { error in
                (error as? OracleSQLError)?.code == .unsupportedDataType
            })
    }

    @Test func trimLOB() async throws {
        let data = try Data(contentsOf: fileURL)
        let buffer = ByteBuffer(bytes: Array(data))

        try await runPopulatedTest { connection, tableName in
            try await connection.execute(
                "INSERT INTO \(unescaped: tableName) (id, content) VALUES (1, \(buffer))",
                logger: .oracleTest
            )
            try await self.validateLOB(expected: buffer, tableName: tableName, on: connection)

            let optionalLOB = try await connection.execute(
                "SELECT content FROM \(unescaped: tableName) WHERE id = 1",
                options: .init(fetchLOBs: true)
            ).collect().first?.decode(LOB.self)
            let lob = try #require(optionalLOB)

            // shrink to half size
            try await lob.trim(to: buffer.readableBytes / 2, on: connection)

            let trimmed = buffer.getSlice(at: 0, length: buffer.readableBytes / 2)!
            try await self.validateLOB(expected: trimmed, tableName: tableName, on: connection)
        }
    }

    @Test func simpleBinaryLOBConcurrently5Times() async throws {
        let data = try Data(contentsOf: fileURL)
        let buffer = ByteBuffer(bytes: Array(data))

        try await runPopulatedTest { connection, tableName in
            try await connection.execute(
                "INSERT INTO \(unescaped: tableName) (id, content) VALUES (1, \(buffer))",
                logger: .oracleTest
            )
            try await withThrowingTaskGroup(of: OracleRowSequence.self) { [connection] group in
                group.addTask {
                    try await connection.execute(
                        "SELECT id, content FROM \(unescaped: tableName) ORDER BY id",
                        logger: .oracleTest
                    )
                }

                group.addTask {
                    try await connection.execute(
                        "SELECT id, content FROM \(unescaped: tableName) ORDER BY id",
                        logger: .oracleTest
                    )
                }

                group.addTask {
                    try await connection.execute(
                        "SELECT id, content FROM \(unescaped: tableName) ORDER BY id",
                        logger: .oracleTest
                    )
                }

                group.addTask {
                    try await connection.execute(
                        "SELECT id, content FROM \(unescaped: tableName) ORDER BY id",
                        logger: .oracleTest
                    )
                }

                group.addTask {
                    try await connection.execute(
                        "SELECT id, content FROM \(unescaped: tableName) ORDER BY id",
                        logger: .oracleTest
                    )
                }

                for try await rows in group {
                    for try await row in rows.decode((Int, ByteBuffer).self) {
                        #expect(1 == row.0)
                        #expect(row.1 == buffer)
                        #expect(
                            row.1.getString(at: 0, length: row.1.readableBytes)
                                == buffer.getString(at: 0, length: buffer.readableBytes)
                        )
                    }
                }
            }
        }
    }


    private func validateLOB(
        expected: ByteBuffer,
        tableName: String,
        on connection: OracleConnection,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let rows = try await connection.execute(
            "SELECT id, content FROM \(unescaped: tableName) ORDER BY id",
            logger: .oracleTest
        )
        var index = 0
        for try await row in rows.decode((Int, ByteBuffer).self) {
            #expect(index + 1 == row.0)
            index = row.0
            #expect(row.1 == expected)
            #expect(
                row.1.getString(at: 0, length: row.1.readableBytes)
                    == expected.getString(at: 0, length: expected.readableBytes)
            )
        }
    }
}
