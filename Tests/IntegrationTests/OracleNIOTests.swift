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
import NIOPosix
import OracleNIO
import XCTest

final class OracleNIOTests: XCTestCase {

    private var group: EventLoopGroup!

    private var eventLoop: EventLoop { self.group.next() }

    override func setUpWithError() throws {
        try super.setUpWithError()
        if env("SMOKE_TEST_ONLY") == "1" {
            throw XCTSkip("Skipping... running only smoke test suite")
        }

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

    func testMultipleFailingAttempts() async throws {
        var config = OracleConnection.Configuration(
            host: env("ORA_HOSTNAME") ?? "192.168.1.24",
            port: env("ORA_PORT").flatMap(Int.init) ?? 1521,
            service: .serviceName(env("ORA_SERVICE_NAME") ?? "XEPDB1"),
            username: env("ORA_USERNAME") ?? "my_user",
            password: "wrong_password"
        )
        config.retryCount = 3
        config.retryDelay = 1

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
        let rows = try await conn.execute(
            "SELECT 'test' FROM dual", logger: .oracleTest
        ).collect()
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(try rows.first?.decode(String.self), "test")
    }

    func testSimpleQuery2() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { XCTAssertNoThrow(try conn.syncClose()) }
        let rows = try await conn.execute(
            "SELECT 1 as ID FROM dual", logger: .oracleTest
        ).collect()
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(try rows.first?.decode(Int.self), 1)
    }

    func testSimpleDateQuery() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { XCTAssertNoThrow(try conn.syncClose()) }
        let rows = try await conn.execute(
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
        var rows = try await conn.execute(
            "SELECT \(Optional("test")) FROM dual", logger: .oracleTest
        ).collect()
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(try rows.first?.decode(String?.self), "test")
        rows = try await conn.execute(
            "SELECT \(String?.none) FROM dual", logger: .oracleTest
        ).collect()
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(try rows.first?.decode(String?.self), nil)
    }

    func testQuery10kItems() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { XCTAssertNoThrow(try conn.syncClose()) }

        let rows = try await conn.execute(
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
        let rows = try await conn.execute(
            """
            SELECT to_number(column_value) / 100 AS id
            FROM xmltable ('1 to 100')
            """,
            logger: .oracleTest
        )
        for try await row in rows {
            func workaround() {
                var number: Float?
                XCTAssertNoThrow(
                    number = try row.decode(
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
            try await conn.execute(
                "DROP TABLE duplicate", logger: .oracleTest
            )
        } catch let error as OracleSQLError {
            // "ORA-00942: table or view does not exist" can be ignored
            XCTAssertEqual(error.serverInfo?.number, 942)
        }
        try await conn.execute(
            "CREATE TABLE duplicate (id number, title varchar2(150 byte))",
            logger: .oracleTest
        )
        try await conn.execute(
            "INSERT INTO duplicate (id, title) VALUES (1, 'hello!')",
            logger: .oracleTest
        )
        try await conn.execute(
            "INSERT INTO duplicate (id, title) VALUES (2, 'hi!')",
            logger: .oracleTest
        )
        try await conn.execute(
            "INSERT INTO duplicate (id, title) VALUES (3, 'hello, there!')",
            logger: .oracleTest
        )
        try await conn.execute(
            "INSERT INTO duplicate (id, title) VALUES (4, 'hello, there!')",
            logger: .oracleTest
        )
        try await conn.execute(
            "INSERT INTO duplicate (id, title) VALUES (5, 'hello, guys!')",
            logger: .oracleTest
        )
        let rows = try await conn.execute(
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
        try await conn.execute("DROP TABLE duplicate", logger: .oracleTest)
    }

    func testDuplicateColumnInEveryRow() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { XCTAssertNoThrow(try conn.syncClose()) }
        do {
            try await conn.execute(
                "DROP TABLE duplicate", logger: .oracleTest
            )
        } catch let error as OracleSQLError {
            // "ORA-00942: table or view does not exist" can be ignored
            XCTAssertEqual(error.serverInfo?.number, 942)
        }
        try await conn.execute(
            "CREATE TABLE duplicate (id number, title varchar2(150 byte))",
            logger: .oracleTest
        )
        try await conn.execute(
            "INSERT INTO duplicate (id, title) VALUES (1, 'hello!')",
            logger: .oracleTest
        )
        try await conn.execute(
            "INSERT INTO duplicate (id, title) VALUES (2, 'hello!')",
            logger: .oracleTest
        )
        try await conn.execute(
            "INSERT INTO duplicate (id, title) VALUES (3, 'hello!')",
            logger: .oracleTest
        )
        try await conn.execute(
            "INSERT INTO duplicate (id, title) VALUES (4, 'hello!')",
            logger: .oracleTest
        )
        try await conn.execute(
            "INSERT INTO duplicate (id, title) VALUES (5, 'hello!')",
            logger: .oracleTest
        )
        let rows = try await conn.execute(
            "SELECT id, title FROM duplicate ORDER BY id", logger: .oracleTest
        )
        var index = 0
        for try await row in rows.decode((Int, String).self) {
            XCTAssertEqual(index + 1, row.0)
            index = row.0
            XCTAssertEqual(row.1, "hello!")
        }
        try await conn.execute("DROP TABLE duplicate", logger: .oracleTest)
    }

    func testNoRowsQueryFromDual() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { XCTAssertNoThrow(try conn.syncClose()) }
        let rows = try await conn.execute(
            "SELECT null FROM dual where rownum = 0", logger: .oracleTest
        ).collect()
        XCTAssertEqual(rows.count, 0)
    }

    func testNoRowsQueryFromActual() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { XCTAssertNoThrow(try conn.syncClose()) }
        do {
            try await conn.execute(
                "DROP TABLE empty", logger: .oracleTest
            )
        } catch let error as OracleSQLError {
            // "ORA-00942: table or view does not exist" can be ignored
            XCTAssertEqual(error.serverInfo?.number, 942)
        }
        try await conn.execute(
            "CREATE TABLE empty (id number, title varchar2(150 byte))",
            logger: .oracleTest
        )
        let rows = try await conn.execute(
            "SELECT id, title FROM empty ORDER BY id", logger: .oracleTest
        ).collect()
        XCTAssertEqual(rows.count, 0)
        try await conn.execute("DROP TABLE empty", logger: .oracleTest)
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
            try await conn1.execute(
                "DROP TABLE test_commit", logger: .oracleTest
            )
        } catch let error as OracleSQLError {
            // "ORA-00942: table or view does not exist" can be ignored
            XCTAssertEqual(error.serverInfo?.number, 942)
        }
        try await conn1.execute(
            "CREATE TABLE test_commit (id number, title varchar2(150 byte))",
            logger: .oracleTest
        )
        try await conn1.execute(
            "INSERT INTO test_commit (id, title) VALUES (1, 'hello!')",
            logger: .oracleTest
        )
        let rows = try await conn1.execute(
            "SELECT id, title FROM test_commit ORDER BY id", logger: .oracleTest
        )
        var index = 0
        for try await row in rows.decode((Int, String).self) {
            XCTAssertEqual(index + 1, row.0)
            index = row.0
            XCTAssertEqual(row.1, "hello!")
        }

        let rowCountOnConn2BeforeCommit = try await conn2.execute(
            "SELECT id, title FROM test_commit ORDER BY id", logger: .oracleTest
        ).collect().count
        XCTAssertEqual(rowCountOnConn2BeforeCommit, 0)

        try await conn1.commit()

        let rowsFromConn2AfterCommit = try await conn2.execute(
            "SELECT id, title FROM test_commit ORDER BY id", logger: .oracleTest
        )
        index = 0
        for try await row
            in rowsFromConn2AfterCommit
            .decode((Int, String).self)
        {
            XCTAssertEqual(index + 1, row.0)
            index = row.0
            XCTAssertEqual(row.1, "hello!")
        }

        try await conn1.execute("DROP TABLE test_commit", logger: .oracleTest)
    }

    func testRollback() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { XCTAssertNoThrow(try conn.syncClose()) }
        do {
            try await conn.execute(
                "DROP TABLE test_rollback", logger: .oracleTest
            )
        } catch let error as OracleSQLError {
            // "ORA-00942: table or view does not exist" can be ignored
            XCTAssertEqual(error.serverInfo?.number, 942)
        }
        try await conn.execute(
            "CREATE TABLE test_rollback (id number, title varchar2(150 byte))",
            logger: .oracleTest
        )
        try await conn.execute(
            "INSERT INTO test_rollback (id, title) VALUES (1, 'hello!')",
            logger: .oracleTest
        )
        let rows = try await conn.execute(
            "SELECT id, title FROM test_rollback ORDER BY id", logger: .oracleTest
        )
        var index = 0
        for try await row in rows.decode((Int, String).self) {
            XCTAssertEqual(index + 1, row.0)
            index = row.0
            XCTAssertEqual(row.1, "hello!")
        }

        try await conn.rollback()

        let rowCountAfterCommit = try await conn.execute(
            "SELECT id, title FROM test_rollback ORDER BY id", logger: .oracleTest
        ).collect().count
        XCTAssertEqual(rowCountAfterCommit, 0)

        try await conn.execute("DROP TABLE test_rollback", logger: .oracleTest)
    }

    func testSimplePlSQL() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { XCTAssertNoThrow(try conn.syncClose()) }

        let input = 42
        try await conn.execute(
            """
            declare
            result number;
            begin
            result := \(OracleNumber(input)) + 69;
            end;
            """, logger: .oracleTest)
    }

    func testSimpleMalformedPlSQL() async throws {
        do {
            let conn = try await OracleConnection.test(on: self.eventLoop)
            defer { XCTAssertNoThrow(try conn.syncClose()) }

            let input = 42
            // The following query misses a required semicolon in line 4
            try await conn.execute(
                """
                declare
                result number;
                begin
                result := \(OracleNumber(input)) + 69
                end;
                """, logger: .oracleTest)
        } catch let error as OracleSQLError {
            XCTAssertEqual(error.serverInfo?.number, 6550)
        }
    }

    func testEmptyStringBind() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { XCTAssertNoThrow(try conn.syncClose()) }

        let row =
            try await conn
            .execute("SELECT \("") FROM dual", logger: .oracleTest)
            .collect()
            .first
        XCTAssertNil(try row?.decode(String?.self))
        XCTAssertEqual(try row?.decode(String.self), "")
    }

    func testOutBind() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { XCTAssertNoThrow(try conn.syncClose()) }
        // table creation errors can be ignored
        _ = try? await conn.execute("CREATE TABLE test_out (value number)", logger: .oracleTest)

        let out = OracleRef(dataType: .number, isReturnBind: true)
        try await conn.execute(
            """
            INSERT INTO test_out VALUES (\(OracleNumber(1)))
            RETURNING value INTO \(out)
            """, logger: .oracleTest)
        XCTAssertEqual(try out.decode(), 1)

        _ = try? await conn.execute("DROP TABLE test_out", logger: .oracleTest)
    }

    func testOutBindInPLSQL() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { XCTAssertNoThrow(try conn.syncClose()) }
        let out = OracleRef(dataType: .number)
        try await conn.execute(
            """
            begin
            \(out) := \(OracleNumber(8)) + \(OracleNumber(7));
            end;
            """, logger: .oracleTest)
        XCTAssertEqual(try out.decode(), 15)
    }

    func testOutBindDuplicateInPLSQL() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { XCTAssertNoThrow(try conn.syncClose()) }
        let out1 = OracleRef(dataType: .number)
        let out2 = OracleRef(dataType: .number)
        try await conn.execute(
            """
            begin
            \(out1) := \(OracleNumber(8)) + \(OracleNumber(7));
            \(out2) := 15;
            end;
            """, logger: .oracleTest)
        XCTAssertEqual(try out1.decode(), 15)
        XCTAssertEqual(try out2.decode(), 15)
    }

    func testInOutBindInPLSQL() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { XCTAssertNoThrow(try conn.syncClose()) }
        let ref = OracleRef(OracleNumber(25))
        try await conn.execute(
            """
            begin
            \(ref) := \(ref) + \(OracleNumber(8)) + \(OracleNumber(7));
            end;
            """, logger: .oracleTest)
        XCTAssertEqual(try ref.decode(), 40)
    }

    /// Reference: [#6](https://github.com/lovetodream/oracle-nio/issues/6)
    func testMultipleRowsWithFourColumnsWork() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { XCTAssertNoThrow(try conn.syncClose()) }
        let result = try await conn.execute(
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
    }

    func testDecodingFailureInStreamCausesDecodingError() async throws {
        var received: Int64 = 0
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { XCTAssertNoThrow(try conn.syncClose()) }
        do {
            let rows = try await conn.execute(
                "SELECT CASE TO_NUMBER(column_value) WHEN 6969 THEN NULL ELSE TO_NUMBER(column_value) END AS id FROM xmltable ('1 to 10000')",
                logger: .oracleTest
            )
            for try await _ in rows.decode(Int64.self) {
                received += 1
            }
        } catch is OracleDecodingError {
            // desired result
            XCTAssertEqual(received, 6968)
        }
    }

    func testPingAndCloseDontCrash() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        Task {
            try await conn.ping()  // on different thread
        }
        try await conn.close()
    }

    func testDatesOrCorrectlyCoded() async throws {
        let formatter = ISO8601DateFormatter()
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { XCTAssertNoThrow(try conn.syncClose()) }
        let date = Date(timeIntervalSince1970: 1705920378.71279)
        let dateFromStrFn =
            #"TO_TIMESTAMP_TZ('2024-01-22T10:46:18+00:00', 'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM')"#
        var bindings = OracleBindings(capacity: 1)
        bindings.append(date, context: .default, bindName: "1")
        let dateQuery = OracleStatement(
            unsafeSQL:
                "SELECT :1, \(dateFromStrFn), TO_CHAR(\(dateFromStrFn), 'YYYY-MM-DD\"T\"HH24:MI:SSTZH:TZM') FROM DUAL",
            binds: bindings)
        try await conn.execute("ALTER SESSION SET TIME_ZONE = '+01:00'")  // Europe/Berlin
        let datesBerlin = try await conn.execute(dateQuery).collect().first!.decode(
            (Date, Date, String).self)
        XCTAssertEqual(
            Calendar.current.compare(date, to: datesBerlin.0, toGranularity: .second), .orderedSame)
        XCTAssertEqual(
            Calendar.current.compare(datesBerlin.0, to: datesBerlin.1, toGranularity: .second),
            .orderedSame)
        XCTAssertEqual(
            Calendar.current.compare(
                date, to: try XCTUnwrap(formatter.date(from: datesBerlin.2)), toGranularity: .second
            ), .orderedSame)

        try await conn.execute("ALTER SESSION SET TIME_ZONE = '+00:00'")  // UTC/GMT
        let datesUTC = try await conn.execute(dateQuery).collect().first!.decode(
            (Date, Date, String).self)
        XCTAssertEqual(
            Calendar.current.compare(date, to: datesUTC.0, toGranularity: .second), .orderedSame)
        XCTAssertEqual(
            Calendar.current.compare(datesUTC.0, to: datesUTC.1, toGranularity: .second),
            .orderedSame)
        XCTAssertEqual(
            Calendar.current.compare(
                date, to: try XCTUnwrap(formatter.date(from: datesUTC.2)), toGranularity: .second),
            .orderedSame)

        try await conn.execute("ALTER SESSION SET TIME_ZONE = '-10:00'")  // Hawaii
        let datesHawaii = try await conn.execute(dateQuery).collect().first!.decode(
            (Date, Date, String).self)
        XCTAssertEqual(
            Calendar.current.compare(date, to: datesHawaii.0, toGranularity: .second), .orderedSame)
        XCTAssertEqual(
            Calendar.current.compare(datesHawaii.0, to: datesHawaii.1, toGranularity: .second),
            .orderedSame)
        XCTAssertEqual(
            Calendar.current.compare(
                date, to: try XCTUnwrap(formatter.date(from: datesHawaii.2)), toGranularity: .second
            ), .orderedSame)
    }

    func testUnusedBindDoesNotCrash() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { XCTAssertNoThrow(try conn.syncClose()) }
        let bind = OracleRef(OracleNumber(0))
        try await conn.execute(
            """
            BEGIN
            IF (NULL IS NOT NULL) THEN
            \(bind) := 1;
            END IF;
            END;
            """)
        let result = try bind.decode(of: Int?.self)
        XCTAssertNil(result)
    }

    func testMalformedQuery() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { XCTAssertNoThrow(try conn.syncClose()) }
        do {
            try await conn.execute("\"SELECT 'hello' FROM dual")
        } catch let error as OracleSQLError {
            print(error)
            XCTAssertEqual(error.code, .server)
            XCTAssertEqual(error.serverInfo?.number, 1740)
        }
    }

    func testReturnBindOnNonExistingTableFails() async throws {
        do {
            let conn = try await OracleConnection.test(on: self.eventLoop)
            defer { XCTAssertNoThrow(try conn.syncClose()) }
            let bind = OracleRef(dataType: .number, isReturnBind: true)
            try await conn.execute(
                "INSERT INTO my_non_existing_table(id) VALUES (1) RETURNING id INTO \(bind)",
                logger: .oracleTest)
            _ = try bind.decode(of: Int?.self)
            XCTFail("Query on non existing table did not return an error, but it should have")
        } catch let error as OracleSQLError {
            XCTAssertEqual(error.serverInfo?.number, 942)  // Table or view doesn't exist
        }
    }

    func testReturnBindOnTableWithUnfulfilledConstraintFails() async throws {
        do {
            let conn = try await OracleConnection.test(on: self.eventLoop)
            defer { XCTAssertNoThrow(try conn.syncClose()) }

            // remove preexisting tables
            _ = try? await conn.execute("DROP TABLE my_constrained_table")
            _ = try? await conn.execute("DROP TABLE my_constraint_table")

            // setup tables
            try await conn.execute(
                """
                CREATE TABLE my_constraint_table (
                    id NUMBER GENERATED ALWAYS AS IDENTITY MINVALUE 1 MAXVALUE \
                    9999999999999999999999999999 INCREMENT BY 1 START WITH 1 CACHE \
                    20 NOORDER NOCYCLE NOKEEP NOSCALE,
                    title VARCHAR2(20 BYTE)
                )
                """)
            try await conn.execute(
                "CREATE UNIQUE INDEX my_constraint_table_pk ON my_constraint_table(id)")
            try await conn.execute(
                "ALTER TABLE my_constraint_table ADD CONSTRAINT my_constraint_table_pk PRIMARY KEY(id) USING INDEX ENABLE"
            )

            try await conn.execute(
                """
                CREATE TABLE my_constrained_table (
                    id NUMBER GENERATED ALWAYS AS IDENTITY MINVALUE 1 MAXVALUE \
                    9999999999999999999999999999 INCREMENT BY 1 START WITH 1 CACHE \
                    20 NOORDER NOCYCLE NOKEEP NOSCALE,
                    title VARCHAR2(20 BYTE),
                    my_type NUMBER
                )
                """)
            try await conn.execute(
                "CREATE UNIQUE INDEX my_constrained_table_pk ON my_constrained_table(id)")
            try await conn.execute(
                "ALTER TABLE my_constrained_table ADD CONSTRAINT my_constrained_table_pk PRIMARY KEY(id) USING INDEX ENABLE"
            )
            try await conn.execute(
                "ALTER TABLE my_constrained_table MODIFY (my_type NOT NULL ENABLE)")
            try await conn.execute(
                "ALTER TABLE my_constrained_table ADD CONSTRAINT my_constrained_table_fk1 FOREIGN KEY (my_type) REFERENCES my_constraint_table(id) ENABLE"
            )

            var logger = Logger(label: "test")
            logger.logLevel = .trace
            // execute non-working query
            let bind = OracleRef(dataType: .number, isReturnBind: true)
            try await conn.execute(
                "INSERT INTO my_constrained_table(title, my_type) VALUES ('hello', 2) RETURNING id INTO \(bind)",
                logger: logger)
            _ = try bind.decode(of: Int?.self)
            XCTFail("Query with invalid constraint did not return an error, but it should have")
        } catch let error as OracleSQLError {
            XCTAssertEqual(error.serverInfo?.number, 2291)  // Constraint error
        }
    }

    func testConnectionAttemptCancels() async {
        var config = OracleConnection.Configuration(
            host: env("ORA_HOSTNAME") ?? "192.168.1.24",
            port: env("ORA_PORT").flatMap(Int.init) ?? 1521,
            service: .serviceName(env("ORA_SERVICE_NAME") ?? "XEPDB1"),
            username: env("ORA_USERNAME") ?? "my_user",
            password: "wrong_password"
        )
        config.retryCount = 20
        config.retryDelay = 5
        let configuration = config
        let connect = Task {
            let start = Date().timeIntervalSince1970
            try await withTaskCancellationHandler {
                do {
                    let connection = try await OracleConnection.connect(
                        on: self.eventLoop,
                        configuration: configuration,
                        id: 1,
                        logger: .oracleTest
                    )
                    try await connection.close()
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    XCTFail("Unexpected error: \(String(reflecting: error))")
                }
            } onCancel: {
                let duration = Date().timeIntervalSince1970 - start
                XCTAssert(duration > 8.0 && duration < 10.0)
            }
        }
        try? await Task.sleep(for: .seconds(8))  // should be in the second attempt
        connect.cancel()
    }

    func testPlainQueryWorks() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { XCTAssertNoThrow(try conn.syncClose()) }
        try await conn.execute("COMMIT")
    }

    func testEarlyReturnAfterStreamCompleteDoesNotCrash() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { XCTAssertNoThrow(try conn.syncClose()) }
        let stream = try await conn.execute("SELECT 1 FROM dual UNION ALL SELECT 2 FROM dual")
        for try await (id) in stream.decode(Int.self) {
            XCTAssertEqual(id, 1)
            break
        }
        try await Task.sleep(for: .seconds(0.5))
    }

    func testQueryAfterCancellationDoesNotDeadlock() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { XCTAssertNoThrow(try conn.syncClose()) }

        let rows = try await conn.execute(
            "SELECT to_number(column_value) AS id FROM xmltable ('1 to 10000')",
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
            if (number ?? 0) > 100 {
                break
            }
        }

        let rows2 = try await conn.execute("SELECT 'next_query' FROM dual", logger: .oracleTest)
        var received2 = 0
        for try await row in rows2 {
            XCTAssertEqual("next_query", try? row.decode(String.self))
            received2 += 1
        }
        XCTAssertEqual(received2, 1)
    }

    func testPendingTasksAreExecuted() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { XCTAssertNoThrow(try conn.syncClose()) }

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await conn.ping()
            }
            group.addTask {
                try await conn.ping()
            }

            for try await value in group { value }
        }
    }

    func testStoredProcedure() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { XCTAssertNoThrow(try conn.syncClose()) }

        let createProcedureQuery: OracleStatement = """
            CREATE OR REPLACE PROCEDURE get_length (value VARCHAR2, value_length OUT BINARY_INTEGER) AS
            BEGIN
                SELECT length(value) INTO value_length FROM dual;
            END;
            """
        try await conn.execute(createProcedureQuery)

        let myValue = "Hello, there!"
        let myCountBind = OracleRef(0)
        try await conn.execute(
            """
            BEGIN
                get_length(\(myValue), \(myCountBind));
            END;
            """)
        let myCount = try myCountBind.decode(of: Int.self)
        print(myCount)  // 13
        XCTAssertEqual(myCount, 13)
    }

    func testStoredProcedureWithVarchar() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { XCTAssertNoThrow(try conn.syncClose()) }

        let createProcedureQuery: OracleStatement = """
            CREATE OR REPLACE PROCEDURE get_random_record_test3 (
            value_firstname OUT VARCHAR2
            ) AS
            BEGIN
            value_firstname := 'DummyName';
            END;
            """
        try await conn.execute(createProcedureQuery)

        let myNameBind = OracleRef(dataType: .varchar)
        try await conn.execute(
            """
            BEGIN
                GET_RANDOM_RECORD_TEST3(\(myNameBind));
            END;
            """)
        let myName = try myNameBind.decode(of: String.self)
        XCTAssertEqual(myName, "DummyName")
    }

    func testBasicVectorTable() async throws {
        try XCTSkipIf(env("TEST_VECTORS")?.isEmpty != false)
        let conn = try await OracleConnection.test(on: eventLoop)
        defer { XCTAssertNoThrow(try conn.syncClose()) }
        try await conn.execute(
            """
            CREATE TABLE IF NOT EXISTS sample_vector_table(
                v32 vector(3, float32),
                v64 vector(3, float64),
                v8  vector(3, int8)
            )
            """)
        try await conn.execute("TRUNCATE TABLE sample_vector_table")
        typealias Row = (OracleVectorFloat32?, OracleVectorFloat64, OracleVectorInt8)
        let insertRows: [Row] = [
            ([2.625, 2.5, 2.0], [22.25, 22.75, 22.5], [4, 5, 6]),
            ([3.625, 3.5, 3.0], [33.25, 33.75, 33.5], [7, 8, 9]),
            (nil, [15.75, 18.5, 9.25], [10, 11, 12]),
        ]
        for row in insertRows {
            try await conn.execute(
                "INSERT INTO sample_vector_table (v32, v64, v8) VALUES (\(row.0), \(row.1), \(row.2))"
            )
        }

        let stream = try await conn.execute("SELECT v32, v64, v8 FROM sample_vector_table")
        var selectedRows: [Row] = []
        for try await row in stream.decode(Row.self) {
            selectedRows.append(row)
        }
        XCTAssertTrue(!selectedRows.isEmpty)
        for index in insertRows.indices {
            XCTAssertEqual(insertRows[index].0, selectedRows[index].0)
            XCTAssertEqual(insertRows[index].1, selectedRows[index].1)
            XCTAssertEqual(insertRows[index].2, selectedRows[index].2)
        }
    }

    func testFlexibleVector() async throws {
        try XCTSkipIf(env("TEST_VECTORS")?.isEmpty != false)
        let conn = try await OracleConnection.test(on: eventLoop)
        defer { XCTAssertNoThrow(try conn.syncClose()) }
        try await conn.execute(
            """
            CREATE TABLE IF NOT EXISTS sample_vector_table2(
                v32 vector(*, float32)
            )
            """)
        try await conn.execute("TRUNCATE TABLE sample_vector_table2")
        let vector: OracleVectorFloat32 = [1.1, 2.2, 3.3, 4.4, 5.5]
        try await conn.execute(
            "INSERT INTO sample_vector_table2 (v32) VALUES (\(vector))"
        )

        let stream = try await conn.execute("SELECT v32 FROM sample_vector_table2")
        var selectedRows: [OracleVectorFloat32] = []
        for try await row in stream.decode(OracleVectorFloat32.self) {
            selectedRows.append(row)
        }
        XCTAssertEqual(selectedRows.count, 1)
        XCTAssertEqual(selectedRows[0], vector)
    }

    func testDomainAndAnnotations() async throws {
        try XCTSkipIf(env("TEST_PRIVILEGED")?.isEmpty != false)
        let conn = try await OracleConnection.test(
            on: eventLoop, config: OracleConnection.privilegedTestConfig()
        )
        defer { XCTAssertNoThrow(try conn.syncClose()) }

        try await conn.execute("drop table if exists emp_annotated")
        try await conn.execute("create domain if not exists SimpleDomain as number(3, 0) NOT NULL")
        try await conn.execute(
            """
            create table emp_annotated(
                empno number domain SimpleDomain,
                ename varchar2(50) annotations (display 'lastname'),
                salary number      annotations (person_salary, column_hidden)
            ) annotations (display 'employees')
            """)
        try await conn.execute("select * from emp_annotated")
    }

    func testLONGBindBeforeNonLONGBindWorks() async throws {
        var buffer = ByteBuffer()
        buffer.reserveCapacity("binary data".utf8.count * 5000)
        for _ in 0..<5000 {
            buffer.writeString("binary data")
        }
        let conn = try await OracleConnection.test(on: eventLoop)
        defer { XCTAssertNoThrow(try conn.syncClose()) }

        _ = try? await conn.execute("DROP TABLE buffer_test_table")
        try await conn.execute(
            "CREATE TABLE buffer_test_table (id number, mimetype varchar2(50), filename varchar2(100), data blob)"
        )
        try await conn.execute(
            "INSERT INTO buffer_test_table (id, mimetype, filename, data) VALUES (\(OracleNumber(1)), \("image/jpeg"), \("image.jpeg"), \(buffer))"
        )
        let stream1 = try await conn.execute(
            "SELECT data, filename FROM buffer_test_table WHERE id = \(OracleNumber(1))")
        for try await (data, filename) in stream1.decode((ByteBuffer, String).self) {
            XCTAssertEqual(data, buffer)
            XCTAssertEqual(filename, "image.jpeg")
        }
        buffer.clear(minimumCapacity: "binory doto".utf8.count * 5000)
        for _ in 0..<5000 {
            buffer.writeString("binory doto")
        }
        try await conn.execute(
            "UPDATE buffer_test_table SET data = \(buffer) WHERE id = \(OracleNumber(1))")
        let stream2 = try await conn.execute(
            "SELECT data, filename FROM buffer_test_table WHERE id = \(OracleNumber(1))")
        for try await (data, filename) in stream2.decode((ByteBuffer, String).self) {
            XCTAssertEqual(data, buffer)
            XCTAssertEqual(filename, "image.jpeg")
        }
    }

    func testCursor() async throws {
        let conn = try await OracleConnection.test(on: eventLoop)
        defer { XCTAssertNoThrow(try conn.syncClose()) }

        try await conn.execute(
            """
            CREATE OR REPLACE PROCEDURE TESTREPORT77 (
            num_samples IN NUMBER,
            result OUT SYS_REFCURSOR
            ) IS
            alphabet VARCHAR2(26) := 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'; -- Alphabets string
            BEGIN
            -- Opening the cursor for the result set
            OPEN result FOR
            SELECT eofficeId AS input_value,
                   TO_CHAR(eofficeId * 2) AS doubled_value_str, -- Representing doubled_value as string
                   SUBSTR(alphabet, 1, eofficeId) AS alphabets, -- Selecting alphabets based on input value
                   eofficeId * 2 AS doubled_value,
                   eofficeId + 10 AS increased_value
            FROM (
                SELECT LEVEL AS eofficeId
                FROM DUAL
                CONNECT BY LEVEL <= num_samples
            )
            ORDER BY DBMS_RANDOM.VALUE;
            END;
            """)
        let cursorRef = OracleRef(dataType: .cursor)
        try await conn.execute("BEGIN testreport77(50, \(cursorRef)); END;")
        let cursor = try cursorRef.decode(of: Cursor.self)
        XCTAssertEqual(
            cursor.columns.map(\.name),
            ["INPUT_VALUE", "DOUBLED_VALUE_STR", "ALPHABETS", "DOUBLED_VALUE", "INCREASED_VALUE"]
        )
        let stream = try await cursor.execute(on: conn)
        var received = 0
        for try await _ in stream.decode((Int, String, String, Int, Int).self) {
            received += 1
        }
        XCTAssertEqual(received, 50)

        // Cannot be executed again
        var secondSucceeded = true
        do {
            _ = try await cursor.execute(on: conn)
        } catch {
            secondSucceeded = false
            let error = try XCTUnwrap(error as? OracleSQLError)
            XCTAssertEqual(error.code, .server)
            XCTAssertEqual(error.serverInfo?.number, 1001)  // unknown cursor id
        }
        XCTAssertFalse(secondSucceeded)
    }

    func testRowID() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { XCTAssertNoThrow(try conn.syncClose()) }
        _ = try? await conn.execute("DROP TABLE row_id_test")
        try await conn.execute("CREATE TABLE row_id_test (id NUMBER)")
        var insertStatement: OracleStatement = "INSERT ALL "
        for i in 1...50 {
            insertStatement.sql.append("INTO row_id_test (id) VALUES (:\(i))")
            insertStatement.binds.append(OracleNumber(i), context: .default, bindName: "\(i)")
        }
        insertStatement.sql.append(" SELECT 1 FROM DUAL")
        try await conn.execute(insertStatement)
        let stream = try await conn.execute("SELECT rowid, id FROM row_id_test ORDER BY id ASC")
        var currentID = 0
        var firstRowID: RowID?
        for try await (rowID, id) in stream.decode((RowID, Int).self) {
            currentID += 1
            XCTAssertEqual(currentID, id)
            if currentID == 1 {
                firstRowID = rowID
            }
        }
        XCTAssertEqual(currentID, 50)
        let rowID = try XCTUnwrap(firstRowID)
        let singleRowStream =
            try await conn
            .execute("SELECT rowid, id FROM row_id_test WHERE rowid = \(rowID)")
        currentID = 0
        for try await (fetchedRowID, id) in singleRowStream.decode((String, Int).self) {
            currentID += 1
            XCTAssertEqual(id, 1)
            XCTAssertEqual(fetchedRowID, rowID.description)
        }
        XCTAssertEqual(currentID, 1)
    }

    func testUnicode() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { XCTAssertNoThrow(try conn.syncClose()) }
        let stream = try await conn.execute("SELECT 'ьми' AS col FROM dual")
        for try await (value) in stream.decode(String.self) {
            XCTAssertEqual(value, "ьми")
        }
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
