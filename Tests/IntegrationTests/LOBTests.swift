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

import Logging
import NIOCore
import OracleNIO
import XCTest

final class LOBTests: XCTIntegrationTest {
    var fileURL: URL!

    override func setUp() async throws {
        try await super.setUp()

        let filePath = try XCTUnwrap(
            Bundle.module.path(
                forResource: "Isaac_Newton-Opticks", ofType: "txt"
            ))
        self.fileURL = URL(fileURLWithPath: filePath)

        do {
            try await connection.execute(
                "DROP TABLE test_simple_blob", logger: .oracleTest
            )
        } catch let error as OracleSQLError {
            // "ORA-00942: table or view does not exist" can be ignored
            XCTAssertEqual(error.serverInfo?.number, 942)
        }
        try await connection.execute(
            "CREATE TABLE test_simple_blob (id number, content blob)",
            logger: .oracleTest
        )
    }

    func testSimpleBinaryLOBViaData() async throws {
        let data = try Data(contentsOf: fileURL)

        try await connection.execute(
            "INSERT INTO test_simple_blob (id, content) VALUES (1, \(data))",
            logger: .oracleTest
        )
        let rows = try await connection.execute(
            "SELECT id, content FROM test_simple_blob ORDER BY id",
            logger: .oracleTest
        )
        var index = 0
        for try await row in rows.decode((Int, Data).self) {
            XCTAssertEqual(index + 1, row.0)
            index = row.0
            XCTAssertEqual(row.1, data)
            XCTAssertEqual(
                String(data: row.1, encoding: .utf8),
                String(data: data, encoding: .utf8)
            )
        }
    }

    func testSimpleBinaryLOBViaByteBuffer() async throws {
        let data = try Data(contentsOf: fileURL)
        let buffer = ByteBuffer(data: data)

        try await connection.execute(
            "INSERT INTO test_simple_blob (id, content) VALUES (1, \(buffer))",
            logger: .oracleTest
        )
        try await validateLOB(expected: buffer, on: connection)
    }

    func testSimpleBinaryLOBViaLOB() async throws {
        let data = try Data(contentsOf: fileURL)
        let buffer = ByteBuffer(data: data)

        try await connection.execute(
            "INSERT INTO test_simple_blob (id, content) VALUES (1, \(buffer))",
            logger: .oracleTest
        )
        func fetchLOB(chunkSize: UInt64?) async throws {
            var queryOptions = StatementOptions()
            queryOptions.fetchLOBs = true
            let rows = try await connection.execute(
                "SELECT id, content FROM test_simple_blob ORDER BY id",
                options: queryOptions,
                logger: .oracleTest
            )
            var index = 0
            for try await (id, lob) in rows.decode((Int, LOB).self) {
                index += 1
                XCTAssertEqual(index, id)
                var out = ByteBuffer()
                for try await var chunk in lob.readChunks(ofSize: chunkSize, on: connection) {
                    out.writeBuffer(&chunk)
                }
                XCTAssertEqual(out, buffer)
                XCTAssertEqual(
                    out.getString(at: 0, length: out.readableBytes),
                    buffer.getString(at: 0, length: buffer.readableBytes)
                )
            }
        }
        try await fetchLOB(chunkSize: nil)  // test with default chunk size
        try await fetchLOB(chunkSize: 4_294_967_295)  // test with huge chunk size
    }

    func testWriteLOBStream() async throws {
        let data = try Data(contentsOf: fileURL)
        var buffer = ByteBuffer(data: data)
        let lobRef = OracleRef(dataType: .blob, isReturnBind: true)
        try await connection.execute(
            "INSERT INTO test_simple_blob (id, content) VALUES (1, empty_blob()) RETURNING content INTO \(lobRef)",
            options: .init(fetchLOBs: true)
        )
        let lob = try lobRef.decode(of: LOB.self)
        var offset: UInt64 = 1
        let chunkSize = 65536
        while buffer.readableBytes > 0,
            let slice =
                buffer
                .readSlice(length: min(chunkSize, buffer.readableBytes))
        {
            try await lob.write(slice, at: offset, on: connection)
            offset += UInt64(slice.readableBytes)
        }
        buffer.moveReaderIndex(to: 0)
        try await validateLOB(expected: buffer, on: connection)
    }

    func testSimpleBinaryLOBConcurrently5Times() async throws {
        let data = try Data(contentsOf: fileURL)
        let buffer = ByteBuffer(data: data)

        try await connection.execute(
            "INSERT INTO test_simple_blob (id, content) VALUES (1, \(buffer))",
            logger: .oracleTest
        )
        try await withThrowingTaskGroup(of: OracleRowSequence.self) { [connection] group in
            let connection = connection!
            group.addTask {
                try await connection.execute(
                    "SELECT id, content FROM test_simple_blob ORDER BY id",
                    logger: .oracleTest
                )
            }

            group.addTask {
                try await connection.execute(
                    "SELECT id, content FROM test_simple_blob ORDER BY id",
                    logger: .oracleTest
                )
            }

            group.addTask {
                try await connection.execute(
                    "SELECT id, content FROM test_simple_blob ORDER BY id",
                    logger: .oracleTest
                )
            }

            group.addTask {
                try await connection.execute(
                    "SELECT id, content FROM test_simple_blob ORDER BY id",
                    logger: .oracleTest
                )
            }

            group.addTask {
                try await connection.execute(
                    "SELECT id, content FROM test_simple_blob ORDER BY id",
                    logger: .oracleTest
                )
            }

            for try await rows in group {
                for try await row in rows.decode((Int, ByteBuffer).self) {
                    XCTAssertEqual(1, row.0)
                    XCTAssertEqual(row.1, buffer)
                    XCTAssertEqual(
                        row.1.getString(at: 0, length: row.1.readableBytes),
                        buffer.getString(at: 0, length: buffer.readableBytes)
                    )
                }
            }
        }
    }


    private func validateLOB(
        expected: ByteBuffer,
        on connection: OracleConnection,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let rows = try await connection.execute(
            "SELECT id, content FROM test_simple_blob ORDER BY id",
            logger: .oracleTest
        )
        var index = 0
        for try await row in rows.decode((Int, ByteBuffer).self) {
            XCTAssertEqual(index + 1, row.0, file: file, line: line)
            index = row.0
            XCTAssertEqual(row.1, expected, file: file, line: line)
            XCTAssertEqual(
                row.1.getString(at: 0, length: row.1.readableBytes),
                expected.getString(at: 0, length: expected.readableBytes),
                file: file, line: line
            )
        }
    }
}
