// Copyright 2024 Timo Zacherl
// SPDX-License-Identifier: Apache-2.0

import XCTest
import NIOCore
import NIOPosix
import Logging
import OracleNIO

final class OracleNIOTests: XCTestCase {

    private var group: EventLoopGroup!

    private var eventLoop: EventLoop { self.group.next() }

    override func setUpWithError() throws {
        try super.setUpWithError()
        XCTAssertTrue(isLoggingConfigured)
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }

    override func tearDownWithError() throws {
        try self.group?.syncShutdownGracefully()
        self.group = nil
        try super.tearDownWithError()
    }

    // MARK: Tests

    func testConnectionAndClose() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        XCTAssertNoThrow(try conn.syncClose())
    }

    func testAuthenticationFailure() async throws {
        let config = OracleConnection.Configuration(
            host: env("ORA_HOSTNAME") ?? "192.168.1.24",
            port: env("ORA_PORT").flatMap(Int.init) ?? 1521,
            service: .serviceName(env("ORA_SERVICE_NAME") ?? "XEPDB1"),
            username: env("ORA_USERNAME") ?? "my_user",
            password: "wrong_password"
        )

        var conn: OracleConnection?
        do {
            conn = try await OracleConnection.connect(
                configuration: config, id: 1, logger: .oracleTest
            )
            XCTFail("Authentication should fail")
        } catch {
            // expected
        }

        // In case of a test failure the connection must be closed.
        XCTAssertNoThrow(try conn?.syncClose())
    }

    func testSimpleQuery() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { XCTAssertNoThrow(try conn.syncClose()) }
        let rows = try await conn.query(
            "SELECT 'test' FROM dual", logger: .oracleTest
        ).collect()
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(try rows.first?.decode(String.self), "test")
    }

    func testSimpleDateQuery() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { XCTAssertNoThrow(try conn.syncClose()) }
        let rows = try await conn.query(
            "SELECT systimestamp FROM dual", logger: .oracleTest
        ).collect()
        XCTAssertEqual(rows.count, 1)
        var value: Date?
        XCTAssertNoThrow(value = try rows.first?.decode(Date.self))
        XCTAssertNoThrow(try XCTUnwrap(value))
    }

    func testSimpleOptionalBinds() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { XCTAssertNoThrow(try conn.syncClose()) }
        var rows = try await conn.query(
            "SELECT \(Optional("test")) FROM dual", logger: .oracleTest
        ).collect()
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(try rows.first?.decode(String?.self), "test")
        rows = try await conn.query(
            "SELECT \(String?.none) FROM dual", logger: .oracleTest
        ).collect()
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(try rows.first?.decode(String?.self), nil)
    }

    func testQuery10kItems() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { XCTAssertNoThrow(try conn.syncClose()) }

        let rows = try await conn.query(
            "SELECT to_number(column_value) AS id FROM xmltable ('1 to 10000')",
            options: .init(arraySize: 1000),
            logger: .oracleTest
        )
        var received: Int64 = 0
        for try await row in rows {
            var number: Int64?
            XCTAssertNoThrow(
                number = try row.decode(Int64.self, context: .default)
            )
            received += 1
            XCTAssertEqual(number, received)
        }

        XCTAssertEqual(received, 10_000)
    }

    func testFloatingPointNumbers() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { XCTAssertNoThrow(try conn.syncClose()) }

        var received: Int64 = 0
        let rows = try await conn.query(
            """
            SELECT to_number(column_value) / 100 AS id
            FROM xmltable ('1 to 100')
            """,
            logger: .oracleTest
        )
        for try await row in rows {
            func workaround() {
                var number: Float?
                XCTAssertNoThrow(number = try row.decode(
                    Float.self, context: .default)
                )
                received += 1
                XCTAssertEqual(number, (Float(received) / 100))
            }

            workaround()
        }

        XCTAssertEqual(received, 100)
    }

    func testDuplicateColumn() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { XCTAssertNoThrow(try conn.syncClose()) }
        do {
            try await conn.query(
                "DROP TABLE duplicate", logger: .oracleTest
            )
        } catch let error as OracleSQLError {
            // "ORA-00942: table or view does not exist" can be ignored
            XCTAssertEqual(error.serverInfo?.number, 942)
        }
        try await conn.query(
            "CREATE TABLE duplicate (id number, title varchar2(150 byte))",
            logger: .oracleTest
        )
        try await conn.query(
            "INSERT INTO duplicate (id, title) VALUES (1, 'hello!')",
            logger: .oracleTest
        )
        try await conn.query(
            "INSERT INTO duplicate (id, title) VALUES (2, 'hi!')",
            logger: .oracleTest
        )
        try await conn.query(
            "INSERT INTO duplicate (id, title) VALUES (3, 'hello, there!')",
            logger: .oracleTest
        )
        try await conn.query(
            "INSERT INTO duplicate (id, title) VALUES (4, 'hello, there!')",
            logger: .oracleTest
        )
        try await conn.query(
            "INSERT INTO duplicate (id, title) VALUES (5, 'hello, guys!')",
            logger: .oracleTest
        )
        let rows = try await conn.query(
            "SELECT id, title FROM duplicate ORDER BY id", logger: .oracleTest
        )
        var index = 0
        for try await row in rows.decode((Int, String).self) {
            XCTAssertEqual(index + 1, row.0)
            index = row.0
            switch index {
            case 1:
                XCTAssertEqual(row.1, "hello!")
            case 2:
                XCTAssertEqual(row.1, "hi!")
            case 3, 4:
                XCTAssertEqual(row.1, "hello, there!")
            case 5:
                XCTAssertEqual(row.1, "hello, guys!")
            default:
                XCTFail()
            }
        }
        try await conn.query("DROP TABLE duplicate", logger: .oracleTest)
    }

    func testDuplicateColumnInEveryRow() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { XCTAssertNoThrow(try conn.syncClose()) }
        do {
            try await conn.query(
                "DROP TABLE duplicate", logger: .oracleTest
            )
        } catch let error as OracleSQLError {
            // "ORA-00942: table or view does not exist" can be ignored
            XCTAssertEqual(error.serverInfo?.number, 942)
        }
        try await conn.query(
            "CREATE TABLE duplicate (id number, title varchar2(150 byte))",
            logger: .oracleTest
        )
        try await conn.query(
            "INSERT INTO duplicate (id, title) VALUES (1, 'hello!')",
            logger: .oracleTest
        )
        try await conn.query(
            "INSERT INTO duplicate (id, title) VALUES (2, 'hello!')",
            logger: .oracleTest
        )
        try await conn.query(
            "INSERT INTO duplicate (id, title) VALUES (3, 'hello!')",
            logger: .oracleTest
        )
        try await conn.query(
            "INSERT INTO duplicate (id, title) VALUES (4, 'hello!')",
            logger: .oracleTest
        )
        try await conn.query(
            "INSERT INTO duplicate (id, title) VALUES (5, 'hello!')",
            logger: .oracleTest
        )
        let rows = try await conn.query(
            "SELECT id, title FROM duplicate ORDER BY id", logger: .oracleTest
        )
        var index = 0
        for try await row in rows.decode((Int, String).self) {
            XCTAssertEqual(index + 1, row.0)
            index = row.0
            XCTAssertEqual(row.1, "hello!")
        }
        try await conn.query("DROP TABLE duplicate", logger: .oracleTest)
    }

    func testNoRowsQueryFromDual() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { XCTAssertNoThrow(try conn.syncClose()) }
        let rows = try await conn.query(
            "SELECT null FROM dual where rownum = 0", logger: .oracleTest
        ).collect()
        XCTAssertEqual(rows.count, 0)
    }

    func testNoRowsQueryFromActual() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { XCTAssertNoThrow(try conn.syncClose()) }
        do {
            try await conn.query(
                "DROP TABLE empty", logger: .oracleTest
            )
        } catch let error as OracleSQLError {
            // "ORA-00942: table or view does not exist" can be ignored
            XCTAssertEqual(error.serverInfo?.number, 942)
        }
        try await conn.query(
            "CREATE TABLE empty (id number, title varchar2(150 byte))",
            logger: .oracleTest
        )
        let rows = try await conn.query(
            "SELECT id, title FROM empty ORDER BY id", logger: .oracleTest
        ).collect()
        XCTAssertEqual(rows.count, 0)
        try await conn.query("DROP TABLE empty", logger: .oracleTest)
    }

    func testPing() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { XCTAssertNoThrow(try conn.syncClose()) }
        try await conn.ping()
    }

    func testCommit() async throws {
        let conn1 = try await OracleConnection.test(on: self.eventLoop)
        let conn2 = try await OracleConnection.test(on: self.eventLoop)
        defer { XCTAssertNoThrow(try conn1.syncClose()) }
        defer { XCTAssertNoThrow(try conn2.syncClose()) }
        do {
            try await conn1.query(
                "DROP TABLE test_commit", logger: .oracleTest
            )
        } catch let error as OracleSQLError {
            // "ORA-00942: table or view does not exist" can be ignored
            XCTAssertEqual(error.serverInfo?.number, 942)
        }
        try await conn1.query(
            "CREATE TABLE test_commit (id number, title varchar2(150 byte))",
            logger: .oracleTest
        )
        try await conn1.query(
            "INSERT INTO test_commit (id, title) VALUES (1, 'hello!')",
            logger: .oracleTest
        )
        let rows = try await conn1.query(
            "SELECT id, title FROM test_commit ORDER BY id", logger: .oracleTest
        )
        var index = 0
        for try await row in rows.decode((Int, String).self) {
            XCTAssertEqual(index + 1, row.0)
            index = row.0
            XCTAssertEqual(row.1, "hello!")
        }

        let rowCountOnConn2BeforeCommit = try await conn2.query(
            "SELECT id, title FROM test_commit ORDER BY id", logger: .oracleTest
        ).collect().count
        XCTAssertEqual(rowCountOnConn2BeforeCommit, 0)

        try await conn1.commit()

        let rowsFromConn2AfterCommit = try await conn2.query(
            "SELECT id, title FROM test_commit ORDER BY id", logger: .oracleTest
        )
        index = 0
        for try await row in rowsFromConn2AfterCommit
            .decode((Int, String).self) {
            XCTAssertEqual(index + 1, row.0)
            index = row.0
            XCTAssertEqual(row.1, "hello!")
        }

        try await conn1.query("DROP TABLE test_commit", logger: .oracleTest)
    }

    func testRollback() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { XCTAssertNoThrow(try conn.syncClose()) }
        do {
            try await conn.query(
                "DROP TABLE test_rollback", logger: .oracleTest
            )
        } catch let error as OracleSQLError {
            // "ORA-00942: table or view does not exist" can be ignored
            XCTAssertEqual(error.serverInfo?.number, 942)
        }
        try await conn.query(
            "CREATE TABLE test_rollback (id number, title varchar2(150 byte))",
            logger: .oracleTest
        )
        try await conn.query(
            "INSERT INTO test_rollback (id, title) VALUES (1, 'hello!')",
            logger: .oracleTest
        )
        let rows = try await conn.query(
            "SELECT id, title FROM test_rollback ORDER BY id", logger: .oracleTest
        )
        var index = 0
        for try await row in rows.decode((Int, String).self) {
            XCTAssertEqual(index + 1, row.0)
            index = row.0
            XCTAssertEqual(row.1, "hello!")
        }

        try await conn.rollback()

        let rowCountAfterCommit = try await conn.query(
            "SELECT id, title FROM test_rollback ORDER BY id", logger: .oracleTest
        ).collect().count
        XCTAssertEqual(rowCountAfterCommit, 0)

        try await conn.query("DROP TABLE test_rollback", logger: .oracleTest)
    }

    func testSimpleBinaryLOBViaData() async throws {
        let filePath = try XCTUnwrap(Bundle.module.path(
            forResource: "Isaac_Newton-Opticks", ofType: "txt"
        ))
        let fileURL = URL(fileURLWithPath: filePath)
        let data = try Data(contentsOf: fileURL)

        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { XCTAssertNoThrow(try conn.syncClose()) }
        do {
            try await conn.query(
                "DROP TABLE test_simple_blob", logger: .oracleTest
            )
        } catch let error as OracleSQLError {
            // "ORA-00942: table or view does not exist" can be ignored
            XCTAssertEqual(error.serverInfo?.number, 942)
        }
        try await conn.query(
            "CREATE TABLE test_simple_blob (id number, content blob)",
            logger: .oracleTest
        )
        try await conn.query(
            "INSERT INTO test_simple_blob (id, content) VALUES (1, \(data))",
            logger: .oracleTest
        )
        let rows = try await conn.query(
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

        try await conn.query("DROP TABLE test_simple_blob", logger: .oracleTest)
    }

    func testSimpleBinaryLOBViaByteBuffer() async throws {
        let filePath = try XCTUnwrap(Bundle.module.path(
            forResource: "Isaac_Newton-Opticks", ofType: "txt"
        ))
        let fileURL = URL(fileURLWithPath: filePath)
        let data = try Data(contentsOf: fileURL)
        let buffer = ByteBuffer(data: data)

        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { XCTAssertNoThrow(try conn.syncClose()) }
        do {
            try await conn.query(
                "DROP TABLE test_simple_blob", logger: .oracleTest
            )
        } catch let error as OracleSQLError {
            // "ORA-00942: table or view does not exist" can be ignored
            XCTAssertEqual(error.serverInfo?.number, 942)
        }
        try await conn.query(
            "CREATE TABLE test_simple_blob (id number, content blob)",
            logger: .oracleTest
        )
        try await conn.query(
            "INSERT INTO test_simple_blob (id, content) VALUES (1, \(buffer))",
            logger: .oracleTest
        )
        let rows = try await conn.query(
            "SELECT id, content FROM test_simple_blob ORDER BY id",
            logger: .oracleTest
        )
        var index = 0
        for try await row in rows.decode((Int, ByteBuffer).self) {
            XCTAssertEqual(index + 1, row.0)
            index = row.0
            XCTAssertEqual(row.1, buffer)
            XCTAssertEqual(
                row.1.getString(at: 0, length: row.1.readableBytes),
                buffer.getString(at: 0, length: buffer.readableBytes)
            )
        }

        try await conn.query("DROP TABLE test_simple_blob", logger: .oracleTest)
    }

    func testSimpleBinaryLOBConcurrently5Times() async throws {
        let filePath = try XCTUnwrap(Bundle.module.path(
            forResource: "Isaac_Newton-Opticks", ofType: "txt"
        ))
        let fileURL = URL(fileURLWithPath: filePath)
        let data = try Data(contentsOf: fileURL)
        let buffer = ByteBuffer(data: data)

        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { XCTAssertNoThrow(try conn.syncClose()) }
        do {
            try await conn.query(
                "DROP TABLE test_simple_blob", logger: .oracleTest
            )
        } catch let error as OracleSQLError {
            // "ORA-00942: table or view does not exist" can be ignored
            XCTAssertEqual(error.serverInfo?.number, 942)
        }
        try await conn.query(
            "CREATE TABLE test_simple_blob (id number, content blob)",
            logger: .oracleTest
        )
        try await conn.query(
            "INSERT INTO test_simple_blob (id, content) VALUES (1, \(buffer))",
            logger: .oracleTest
        )
        try await withThrowingTaskGroup(of: OracleRowSequence.self) { group in
            group.addTask {
                try await conn.query(
                    "SELECT id, content FROM test_simple_blob ORDER BY id",
                    logger: .oracleTest
                )
            }

            group.addTask {
                try await conn.query(
                    "SELECT id, content FROM test_simple_blob ORDER BY id",
                    logger: .oracleTest
                )
            }

            group.addTask {
                try await conn.query(
                    "SELECT id, content FROM test_simple_blob ORDER BY id",
                    logger: .oracleTest
                )
            }

            group.addTask {
                try await conn.query(
                    "SELECT id, content FROM test_simple_blob ORDER BY id",
                    logger: .oracleTest
                )
            }

            group.addTask {
                try await conn.query(
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

        try await conn.query("DROP TABLE test_simple_blob", logger: .oracleTest)
    }

    func testSimplePlSQL() async {
        do {
            let conn = try await OracleConnection.test(on: self.eventLoop)
            defer { XCTAssertNoThrow(try conn.syncClose()) }

            let input = 42
            try await conn.query("""
            declare
            result number;
            begin
            result := \(OracleNumber(input)) + 69;
            end;
            """, logger: .oracleTest)
        } catch {
            XCTFail("Unexpected error: \(String(reflecting: error))")
        }
    }

    func testSimpleMalformedPlSQL() async {
        do {
            let conn = try await OracleConnection.test(on: self.eventLoop)
            defer { XCTAssertNoThrow(try conn.syncClose()) }

            let input = 42
            // The following query misses a required semicolon in line 4
            try await conn.query("""
            declare
            result number;
            begin
            result := \(OracleNumber(input)) + 69
            end;
            """, logger: .oracleTest)
        } catch let error as OracleSQLError {
            XCTAssertEqual(error.serverInfo?.number, 6550)
        } catch {
            XCTFail("Unexpected error: \(String(reflecting: error))")
        }
    }

    func testEmptyStringBind() async {
        do {
            let conn = try await OracleConnection.test(on: self.eventLoop)
            defer { XCTAssertNoThrow(try conn.syncClose()) }

            let row = try await conn
                .query("SELECT \("") FROM dual", logger: .oracleTest)
                .collect()
                .first
            XCTAssertNil(try row?.decode(String?.self))
            XCTAssertEqual(try row?.decode(String.self), "")
        } catch {
            XCTFail("Unexpected error: \(String(reflecting: error))")
        }
    }

    func testOutBind() async {
        do {
            let conn = try await OracleConnection.test(on: self.eventLoop)
            defer { XCTAssertNoThrow(try conn.syncClose()) }
            // table creation errors can be ignored
            _ = try? await conn.query("CREATE TABLE test_out (value number)", logger: .oracleTest)

            let out = OracleRef(dataType: .number, isReturnBind: true)
            try await conn.query("""
            INSERT INTO test_out VALUES (\(OracleNumber(1)))
            RETURNING value INTO \(out)
            """, logger: .oracleTest)
            XCTAssertEqual(try out.decode(), 1)

            _ = try? await conn.query("DROP TABLE test_out", logger: .oracleTest)
        } catch {
            XCTFail("Unexpected error: \(String(reflecting: error))")
        }
    }

    func testOutBindInPLSQL() async {
        do {
            let conn = try await OracleConnection.test(on: self.eventLoop)
            defer { XCTAssertNoThrow(try conn.syncClose()) }
            let out = OracleRef(dataType: .number)
            try await conn.query("""
            begin
            \(out) := \(OracleNumber(8)) + \(OracleNumber(7));
            end;
            """, logger: .oracleTest)
            XCTAssertEqual(try out.decode(), 15)
        } catch {
            XCTFail("Unexpected error: \(String(reflecting: error))")
        }
    }

    func testOutBindDuplicateInPLSQL() async {
        do {
            let conn = try await OracleConnection.test(on: self.eventLoop)
            defer { XCTAssertNoThrow(try conn.syncClose()) }
            let out1 = OracleRef(dataType: .number)
            let out2 = OracleRef(dataType: .number)
            try await conn.query("""
            begin
            \(out1) := \(OracleNumber(8)) + \(OracleNumber(7));
            \(out2) := 15;
            end;
            """, logger: .oracleTest)
            XCTAssertEqual(try out1.decode(), 15)
            XCTAssertEqual(try out2.decode(), 15)
        } catch {
            XCTFail("Unexpected error: \(String(reflecting: error))")
        }
    }

    func testInOutBindInPLSQL() async {
        do {
            let conn = try await OracleConnection.test(on: self.eventLoop)
            defer { XCTAssertNoThrow(try conn.syncClose()) }
            let ref = OracleRef(OracleNumber(25))
            try await conn.query("""
            begin
            \(ref) := \(ref) + \(OracleNumber(8)) + \(OracleNumber(7));
            end;
            """, logger: .oracleTest)
            XCTAssertEqual(try ref.decode(), 40)
        } catch {
            XCTFail("Unexpected error: \(String(reflecting: error))")
        }
    }

    /// Reference: [#6](https://github.com/lovetodream/oracle-nio/issues/6)
    func testMultipleRowsWithFourColumnsWork() async {
        do {
            let conn = try await OracleConnection.test(on: self.eventLoop)
            defer { XCTAssertNoThrow(try conn.syncClose()) }
            let result = try await conn.query(
                """
                SELECT
                    level,
                    sysdate,
                    'user_' || level username,
                    'test' suffix
                FROM dual CONNECT BY level <= 4
                """, logger: .oracleTest
            ).collect()
            var i = 1
            for row in result {
                let (level, _, username, suffix) = try row.decode((Int, Date, String, String).self)
                XCTAssertEqual(level, i)
                XCTAssertEqual(username, "user_\(i)")
                XCTAssertEqual(suffix, "test")
                i += 1
            }
        } catch {
            XCTFail("Unexpected error: \(String(reflecting: error))")
        }
    }

    func testDecodingFailureInStreamCausesDecodingError() async {
        var received: Int64 = 0
        do {
            let conn = try await OracleConnection.test(on: self.eventLoop)
            defer { XCTAssertNoThrow(try conn.syncClose()) }

            let rows = try await conn.query(
                "SELECT CASE TO_NUMBER(column_value) WHEN 6969 THEN NULL ELSE TO_NUMBER(column_value) END AS id FROM xmltable ('1 to 10000')",
                logger: .oracleTest
            )
            for try await _ in rows.decode(Int64.self) {
                received += 1
            }
        } catch is OracleDecodingError {
            // desired result
            XCTAssertEqual(received, 6968)
        } catch {
            XCTFail("Unexpected error: \(String(reflecting: error))")
        }
    }

    func testPingAndCloseDontCrash() async {
        do {
            let conn = try await OracleConnection.test(on: self.eventLoop)
            Task {
                try await conn.ping() // on different thread
            }
            try await conn.close()
        } catch {
            XCTFail("Unexpected error: \(String(reflecting: error))")
        }
    }

    func testDatesOrCorrectlyCoded() async {
        do {
            let formatter = ISO8601DateFormatter()
            let conn = try await OracleConnection.test(on: self.eventLoop)
            defer { XCTAssertNoThrow(try conn.syncClose()) }
            let date = Date(timeIntervalSince1970: 1705920378.71279)
            let dateFromStrFn = #"TO_TIMESTAMP_TZ('2024-01-22T10:46:18+00:00', 'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM')"#
            var bindings = OracleBindings(capacity: 1)
            bindings.append(date, context: .default, bindName: "1")
            let dateQuery = OracleQuery(unsafeSQL: "SELECT :1, \(dateFromStrFn), TO_CHAR(\(dateFromStrFn), 'YYYY-MM-DD\"T\"HH24:MI:SSTZH:TZM') FROM DUAL", binds: bindings)
            try await conn.query("ALTER SESSION SET TIME_ZONE = '+01:00'") // Europe/Berlin
            let datesBerlin = try await conn.query(dateQuery).collect().first!.decode((Date, Date, String).self)
            XCTAssertEqual(Calendar.current.compare(date, to: datesBerlin.0, toGranularity: .second), .orderedSame)
            XCTAssertEqual(Calendar.current.compare(datesBerlin.0, to: datesBerlin.1, toGranularity: .second), .orderedSame)
            XCTAssertEqual(Calendar.current.compare(date, to: try XCTUnwrap(formatter.date(from: datesBerlin.2)), toGranularity: .second), .orderedSame)

            try await conn.query("ALTER SESSION SET TIME_ZONE = '+00:00'") // UTC/GMT
            let datesUTC = try await conn.query(dateQuery).collect().first!.decode((Date, Date, String).self)
            XCTAssertEqual(Calendar.current.compare(date, to: datesUTC.0, toGranularity: .second), .orderedSame)
            XCTAssertEqual(Calendar.current.compare(datesUTC.0, to: datesUTC.1, toGranularity: .second), .orderedSame)
            XCTAssertEqual(Calendar.current.compare(date, to: try XCTUnwrap(formatter.date(from: datesUTC.2)), toGranularity: .second), .orderedSame)

            try await conn.query("ALTER SESSION SET TIME_ZONE = '-10:00'") // Hawaii
            let datesHawaii = try await conn.query(dateQuery).collect().first!.decode((Date, Date, String).self)
            XCTAssertEqual(Calendar.current.compare(date, to: datesHawaii.0, toGranularity: .second), .orderedSame)
            XCTAssertEqual(Calendar.current.compare(datesHawaii.0, to: datesHawaii.1, toGranularity: .second), .orderedSame)
            XCTAssertEqual(Calendar.current.compare(date, to: try XCTUnwrap(formatter.date(from: datesHawaii.2)), toGranularity: .second), .orderedSame)
        } catch {
            XCTFail("Unexpected error: \(String(reflecting: error))")
        }
    }

    func testUnusedBindDoesNotCrash() async throws {
        do {
            let conn = try await OracleConnection.test(on: self.eventLoop)
            defer { XCTAssertNoThrow(try conn.syncClose()) }
            let bind = OracleRef(OracleNumber(0))
            try await conn.query("""
            BEGIN
            IF (NULL IS NOT NULL) THEN
            \(bind) := 1;
            END IF;
            END;
            """)
            let result = try bind.decode(of: Int?.self)
            XCTAssertNil(result)
        } catch {
            XCTFail("Unexpected error: \(String(reflecting: error))")
        }
    }

    func testMalformedQuery() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { XCTAssertNoThrow(try conn.syncClose()) }
        do {
            try await conn.query("\"SELECT 'hello' FROM dual")
        } catch let error as OracleSQLError {
            print(error)
            XCTAssertEqual(error.code, .server)
            XCTAssertEqual(error.serverInfo?.number, 1740)
        } catch {
            XCTFail("Unexpected error: \(String(reflecting: error))")
        }
    }

    func testReturnBindOnNonExistingTableFails() async throws {
        do {
            let conn = try await OracleConnection.test(on: self.eventLoop)
            defer { XCTAssertNoThrow(try conn.syncClose()) }
            let bind = OracleRef(dataType: .number, isReturnBind: true)
            try await conn.query("INSERT INTO my_non_existing_table(id) VALUES (1) RETURNING id INTO \(bind)", logger: .oracleTest)
            _ = try bind.decode(of: Int?.self)
            XCTFail("Query on non existing table did not return an error, but it should have")
        } catch let error as OracleSQLError {
            XCTAssertEqual(error.serverInfo?.number, 942) // Table or view doesn't exist
        } catch {
            XCTFail("Unexpected error: \(String(reflecting: error))")
        }
    }

    func testReturnBindOnTableWithUnfulfilledConstraintFails() async throws {
        do {
            let conn = try await OracleConnection.test(on: self.eventLoop)
            defer { XCTAssertNoThrow(try conn.syncClose()) }

            // remove preexisting tables
            _ = try? await conn.query("DROP TABLE my_constrained_table")
            _ = try? await conn.query("DROP TABLE my_constraint_table")

            // setup tables
            try await conn.query("""
            CREATE TABLE my_constraint_table (
                id NUMBER GENERATED ALWAYS AS IDENTITY MINVALUE 1 MAXVALUE \
                9999999999999999999999999999 INCREMENT BY 1 START WITH 1 CACHE \
                20 NOORDER NOCYCLE NOKEEP NOSCALE,
                title VARCHAR2(20 BYTE)
            )
            """)
            try await conn.query("CREATE UNIQUE INDEX my_constraint_table_pk ON my_constraint_table(id)")
            try await conn.query("ALTER TABLE my_constraint_table ADD CONSTRAINT my_constraint_table_pk PRIMARY KEY(id) USING INDEX ENABLE")

            try await conn.query("""
            CREATE TABLE my_constrained_table (
                id NUMBER GENERATED ALWAYS AS IDENTITY MINVALUE 1 MAXVALUE \
                9999999999999999999999999999 INCREMENT BY 1 START WITH 1 CACHE \
                20 NOORDER NOCYCLE NOKEEP NOSCALE,
                title VARCHAR2(20 BYTE),
                my_type NUMBER
            )
            """)
            try await conn.query("CREATE UNIQUE INDEX my_constrained_table_pk ON my_constrained_table(id)")
            try await conn.query("ALTER TABLE my_constrained_table ADD CONSTRAINT my_constrained_table_pk PRIMARY KEY(id) USING INDEX ENABLE")
            try await conn.query("ALTER TABLE my_constrained_table MODIFY (my_type NOT NULL ENABLE)")
            try await conn.query("ALTER TABLE my_constrained_table ADD CONSTRAINT my_constrained_table_fk1 FOREIGN KEY (my_type) REFERENCES my_constraint_table(id) ENABLE")

            var logger = Logger(label: "test")
            logger.logLevel = .trace
            // execute non-working query
            let bind = OracleRef(dataType: .number, isReturnBind: true)
            try await conn.query("INSERT INTO my_constrained_table(title, my_type) VALUES ('hello', 2) RETURNING id INTO \(bind)", logger: logger)
            _ = try bind.decode(of: Int?.self)
            XCTFail("Query with invalid constraint did not return an error, but it should have")
        } catch let error as OracleSQLError {
            //            XCTAssertEqual(error.serverInfo?.number, 942) // Table or view doesn't exist
            print(String(reflecting: error))
        } catch {
            XCTFail("Unexpected error: \(String(reflecting: error))")
        }
    }

    func testPlainQueryWorks() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { XCTAssertNoThrow(try conn.syncClose()) }
        try await conn.query("COMMIT")
    }

}

let isLoggingConfigured: Bool = {
    LoggingSystem.bootstrap { label in
        var handler = StreamLogHandler.standardOutput(label: label)
        handler.logLevel = Logger.getLogLevel()
        return handler
    }
    return true
}()
