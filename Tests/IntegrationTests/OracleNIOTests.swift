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
import Logging
import NIOCore
import NIOPosix
import OracleNIO
import Testing

import struct Foundation.Calendar
import struct Foundation.Date
import class Foundation.ISO8601DateFormatter

@Suite(.disabled(if: env("SMOKE_TEST_ONLY") == "1", "running only smoke test suite")) final class OracleNIOTests {

    private let group: EventLoopGroup

    private var eventLoop: EventLoop { self.group.next() }

    init() async throws {
        #expect(isLoggingConfigured)
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }

    deinit {
        #expect(throws: Never.self, performing: { try self.group.syncShutdownGracefully() })
    }

    // MARK: Tests

    @Test func connectionAndClose() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        print(conn.serverVersion)
        #expect(throws: Never.self, performing: { try conn.syncClose() })
    }

    @Test func authenticationFailure() async throws {
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
            Issue.record("Authentication should fail")
        } catch {
            // expected
        }

        // In case of a test failure the connection must be closed.
        #expect(throws: Never.self, performing: { try conn?.syncClose() })
    }

    @Test func multipleFailingAttempts() async throws {
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
            Issue.record("Authentication should fail")
        } catch {
            // expected
        }

        // In case of a test failure the connection must be closed.
        #expect(throws: Never.self, performing: { try conn?.syncClose() })
    }

    @Test func simpleQuery() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { #expect(throws: Never.self, performing: { try conn.syncClose() }) }
        let rows = try await conn.execute(
            "SELECT 'test' FROM dual", logger: .oracleTest
        ).collect()
        #expect(rows.count == 1)
        #expect(try rows.first?.decode(String.self) == "test")
    }

    @Test func simpleQuery2() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { #expect(throws: Never.self, performing: { try conn.syncClose() }) }
        let rows = try await conn.execute(
            "SELECT 1 as ID FROM dual", logger: .oracleTest
        ).collect()
        #expect(rows.count == 1)
        #expect(try rows.first?.decode(Int.self) == 1)
    }

    @Test func simpleDateQuery() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { #expect(throws: Never.self, performing: { try conn.syncClose() }) }
        let rows = try await conn.execute(
            "SELECT systimestamp FROM dual", logger: .oracleTest
        ).collect()
        #expect(rows.count == 1)
        let value = try rows.first?.decode(Date.self)
        _ = try #require(value)
    }

    @Test func simpleOptionalBinds() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { #expect(throws: Never.self, performing: { try conn.syncClose() }) }
        var rows = try await conn.execute(
            "SELECT \(Optional("test")) FROM dual", logger: .oracleTest
        ).collect()
        #expect(rows.count == 1)
        #expect(try rows.first?.decode(String?.self) == "test")
        rows = try await conn.execute(
            "SELECT \(String?.none) FROM dual", logger: .oracleTest
        ).collect()
        #expect(rows.count == 1)
        #expect(try rows.first?.decode(String?.self) == nil)
    }

    @Test func query10kItems() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { #expect(throws: Never.self, performing: { try conn.syncClose() }) }

        let rows = try await conn.execute(
            "SELECT to_number(column_value) AS id FROM xmltable ('1 to 10000')",
            options: .init(arraySize: 1000),
            logger: .oracleTest
        )
        var received: Int64 = 0
        for try await row in rows {
            var number: Int64?
            #expect(
                throws: Never.self,
                performing: {
                    number = try row.decode(Int64.self, context: .default)
                })
            received += 1
            #expect(number == received)
        }

        #expect(received == 10_000)
    }

    @Test func floatingPointNumbers() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { #expect(throws: Never.self, performing: { try conn.syncClose() }) }

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
                #expect(
                    throws: Never.self,
                    performing: { number = try row.decode(Float.self, context: .default) }
                )
                received += 1
                #expect(number == (Float(received) / 100))
            }

            workaround()
        }

        #expect(received == 100)
    }

    @Test func duplicateColumn() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { #expect(throws: Never.self, performing: { try conn.syncClose() }) }
        do {
            try await conn.execute(
                "DROP TABLE duplicate", logger: .oracleTest
            )
        } catch let error as OracleSQLError {
            // "ORA-00942: table or view does not exist" can be ignored
            #expect(error.serverInfo?.number == 942)
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
            #expect(index + 1 == row.0)
            index = row.0
            switch index {
            case 1:
                #expect(row.1 == "hello!")
            case 2:
                #expect(row.1 == "hi!")
            case 3, 4:
                #expect(row.1 == "hello, there!")
            case 5:
                #expect(row.1 == "hello, guys!")
            default:
                Issue.record("Unexpected record")
            }
        }
        try await conn.execute("DROP TABLE duplicate", logger: .oracleTest)
    }

    @Test func duplicateColumnInEveryRow() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { #expect(throws: Never.self, performing: { try conn.syncClose() }) }
        do {
            try await conn.execute(
                "DROP TABLE duplicate_every_row", logger: .oracleTest
            )
        } catch let error as OracleSQLError {
            // "ORA-00942: table or view does not exist" can be ignored
            #expect(error.serverInfo?.number == 942)
        }
        try await conn.execute(
            "CREATE TABLE duplicate_every_row (id number, title varchar2(150 byte))",
            logger: .oracleTest
        )
        try await conn.execute(
            "INSERT INTO duplicate_every_row (id, title) VALUES (1, 'hello!')",
            logger: .oracleTest
        )
        try await conn.execute(
            "INSERT INTO duplicate_every_row (id, title) VALUES (2, 'hello!')",
            logger: .oracleTest
        )
        try await conn.execute(
            "INSERT INTO duplicate_every_row (id, title) VALUES (3, 'hello!')",
            logger: .oracleTest
        )
        try await conn.execute(
            "INSERT INTO duplicate_every_row (id, title) VALUES (4, 'hello!')",
            logger: .oracleTest
        )
        try await conn.execute(
            "INSERT INTO duplicate_every_row (id, title) VALUES (5, 'hello!')",
            logger: .oracleTest
        )
        let rows = try await conn.execute(
            "SELECT id, title FROM duplicate_every_row ORDER BY id", logger: .oracleTest
        )
        var index = 0
        for try await row in rows.decode((Int, String).self) {
            #expect(index + 1 == row.0)
            index = row.0
            #expect(row.1 == "hello!")
        }
        try await conn.execute("DROP TABLE duplicate_every_row", logger: .oracleTest)
    }

    @Test func noRowsQueryFromDual() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { #expect(throws: Never.self, performing: { try conn.syncClose() }) }
        let rows = try await conn.execute(
            "SELECT null FROM dual where rownum = 0", logger: .oracleTest
        ).collect()
        #expect(rows.count == 0)
    }

    @Test func noRowsQueryFromActual() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { #expect(throws: Never.self, performing: { try conn.syncClose() }) }
        do {
            try await conn.execute(
                "DROP TABLE empty", logger: .oracleTest
            )
        } catch let error as OracleSQLError {
            // "ORA-00942: table or view does not exist" can be ignored
            #expect(error.serverInfo?.number == 942)
        }
        try await conn.execute(
            "CREATE TABLE empty (id number, title varchar2(150 byte))",
            logger: .oracleTest
        )
        let rows = try await conn.execute(
            "SELECT id, title FROM empty ORDER BY id", logger: .oracleTest
        ).collect()
        #expect(rows.count == 0)
        try await conn.execute("DROP TABLE empty", logger: .oracleTest)
    }

    @Test func ping() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { #expect(throws: Never.self, performing: { try conn.syncClose() }) }
        try await conn.ping()
    }

    @Test func commit() async throws {
        try await withOracleConnection { conn1 in
            do {
                try await conn1.execute(
                    "DROP TABLE test_commit", logger: .oracleTest
                )
            } catch let error as OracleSQLError {
                // "ORA-00942: table or view does not exist" can be ignored
                #expect(error.serverInfo?.number == 942)
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
                #expect(index + 1 == row.0)
                index = row.0
                #expect(row.1 == "hello!")
            }

            try await withOracleConnection { conn2 in
                let rowCountOnConn2BeforeCommit = try await conn2.execute(
                    "SELECT id, title FROM test_commit ORDER BY id", logger: .oracleTest
                ).collect().count
                #expect(rowCountOnConn2BeforeCommit == 0)

                try await conn1.commit()

                let rowsFromConn2AfterCommit = try await conn2.execute(
                    "SELECT id, title FROM test_commit ORDER BY id", logger: .oracleTest
                )
                index = 0
                for try await row
                    in rowsFromConn2AfterCommit
                    .decode((Int, String).self)
                {
                    #expect(index + 1 == row.0)
                    index = row.0
                    #expect(row.1 == "hello!")
                }
            }

            try await conn1.execute("DROP TABLE test_commit", logger: .oracleTest)
        }
    }

    @Test func rollback() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { #expect(throws: Never.self, performing: { try conn.syncClose() }) }
        do {
            try await conn.execute(
                "DROP TABLE test_rollback", logger: .oracleTest
            )
        } catch let error as OracleSQLError {
            // "ORA-00942: table or view does not exist" can be ignored
            #expect(error.serverInfo?.number == 942)
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
            #expect(index + 1 == row.0)
            index = row.0
            #expect(row.1 == "hello!")
        }

        try await conn.rollback()

        let rowCountAfterCommit = try await conn.execute(
            "SELECT id, title FROM test_rollback ORDER BY id", logger: .oracleTest
        ).collect().count
        #expect(rowCountAfterCommit == 0)

        try await conn.execute("DROP TABLE test_rollback", logger: .oracleTest)
    }

    @Test func simplePlSQL() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { #expect(throws: Never.self, performing: { try conn.syncClose() }) }

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

    @Test func simpleMalformedPlSQL() async throws {
        do {
            let conn = try await OracleConnection.test(on: self.eventLoop)
            defer { #expect(throws: Never.self, performing: { try conn.syncClose() }) }

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
            #expect(error.serverInfo?.number == 6550)
        }
    }

    @Test func emptyStringBind() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { #expect(throws: Never.self, performing: { try conn.syncClose() }) }

        let row =
            try await conn
            .execute("SELECT \("") FROM dual", logger: .oracleTest)
            .collect()
            .first
        #expect(try row?.decode(String?.self) == nil)
        #expect(try row?.decode(String.self) == "")
    }

    @Test func outBind() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { #expect(throws: Never.self, performing: { try conn.syncClose() }) }
        // table creation errors can be ignored
        _ = try? await conn.execute("CREATE TABLE test_out (value number)", logger: .oracleTest)

        let out = OracleRef(dataType: .number, isReturnBind: true)
        try await conn.execute(
            """
            INSERT INTO test_out VALUES (\(OracleNumber(1)))
            RETURNING value INTO \(out)
            """, logger: .oracleTest)
        #expect(try out.decode() == 1)

        _ = try? await conn.execute("DROP TABLE test_out", logger: .oracleTest)
    }

    @Test func outBindInPLSQL() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { #expect(throws: Never.self, performing: { try conn.syncClose() }) }
        let out = OracleRef(dataType: .number)
        try await conn.execute(
            """
            begin
            \(out) := \(OracleNumber(8)) + \(OracleNumber(7));
            end;
            """, logger: .oracleTest)
        #expect(try out.decode() == 15)
    }

    @Test func outBindDuplicateInPLSQL() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { #expect(throws: Never.self, performing: { try conn.syncClose() }) }
        let out1 = OracleRef(dataType: .number)
        let out2 = OracleRef(dataType: .number)
        try await conn.execute(
            """
            begin
            \(out1) := \(OracleNumber(8)) + \(OracleNumber(7));
            \(out2) := 15;
            end;
            """, logger: .oracleTest)
        #expect(try out1.decode() == 15)
        #expect(try out2.decode() == 15)
    }

    @Test func inOutBindInPLSQL() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { #expect(throws: Never.self, performing: { try conn.syncClose() }) }
        let ref = OracleRef(OracleNumber(25))
        try await conn.execute(
            """
            begin
            \(ref) := \(ref) + \(OracleNumber(8)) + \(OracleNumber(7));
            end;
            """, logger: .oracleTest)
        #expect(try ref.decode() == 40)
    }

    @Test(.bug("https://github.com/lovetodream/oracle-nio/issues/6"))
    func multipleRowsWithFourColumnsWork() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { #expect(throws: Never.self, performing: { try conn.syncClose() }) }
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
            #expect(level == i)
            #expect(username == "user_\(i)")
            #expect(suffix == "test")
            i += 1
        }
    }

    @Test func decodingFailureInStreamCausesDecodingError() async throws {
        var received: Int64 = 0
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { #expect(throws: Never.self, performing: { try conn.syncClose() }) }
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
            #expect(received == 6968)
        }
    }

    @Test func pingAndCloseDontCrash() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        Task {
            try await conn.ping()  // on different thread
        }
        try await conn.close()
    }

    @Test func datesOrCorrectlyCoded() async throws {
        let formatter = ISO8601DateFormatter()
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { #expect(throws: Never.self, performing: { try conn.syncClose() }) }
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
        #expect(
            Calendar.current.compare(date, to: datesBerlin.0, toGranularity: .second) == .orderedSame)
        #expect(
            Calendar.current.compare(datesBerlin.0, to: datesBerlin.1, toGranularity: .second) == .orderedSame)
        #expect(
            Calendar.current.compare(
                date, to: try #require(formatter.date(from: datesBerlin.2)), toGranularity: .second
            ) == .orderedSame)

        try await conn.execute("ALTER SESSION SET TIME_ZONE = '+00:00'")  // UTC/GMT
        let datesUTC = try await conn.execute(dateQuery).collect().first!.decode(
            (Date, Date, String).self)
        #expect(
            Calendar.current.compare(date, to: datesUTC.0, toGranularity: .second) == .orderedSame)
        #expect(
            Calendar.current.compare(datesUTC.0, to: datesUTC.1, toGranularity: .second) == .orderedSame)
        #expect(
            Calendar.current.compare(
                date, to: try #require(formatter.date(from: datesUTC.2)), toGranularity: .second) == .orderedSame)

        try await conn.execute("ALTER SESSION SET TIME_ZONE = '-10:00'")  // Hawaii
        let datesHawaii = try await conn.execute(dateQuery).collect().first!.decode(
            (Date, Date, String).self)
        #expect(
            Calendar.current.compare(date, to: datesHawaii.0, toGranularity: .second) == .orderedSame)
        #expect(
            Calendar.current.compare(datesHawaii.0, to: datesHawaii.1, toGranularity: .second) == .orderedSame)
        #expect(
            Calendar.current.compare(
                date, to: try #require(formatter.date(from: datesHawaii.2)), toGranularity: .second
            ) == .orderedSame)
    }

    @Test func unusedBindDoesNotCrash() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { #expect(throws: Never.self, performing: { try conn.syncClose() }) }
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
        #expect(result == nil)
    }

    @Test func malformedQuery() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { #expect(throws: Never.self, performing: { try conn.syncClose() }) }
        do {
            try await conn.execute("\"SELECT 'hello' FROM dual")
        } catch let error as OracleSQLError {
            print(error)
            #expect(error.code == .server)
            #expect(error.serverInfo?.number == 1740)
        }
    }

    @Test func returnBindOnNonExistingTableFails() async throws {
        do {
            let conn = try await OracleConnection.test(on: self.eventLoop)
            defer { #expect(throws: Never.self, performing: { try conn.syncClose() }) }
            let bind = OracleRef(dataType: .number, isReturnBind: true)
            try await conn.execute(
                "INSERT INTO my_non_existing_table(id) VALUES (1) RETURNING id INTO \(bind)",
                logger: .oracleTest)
            _ = try bind.decode(of: Int?.self)
            Issue.record("Query on non existing table did not return an error, but it should have")
        } catch let error as OracleSQLError {
            #expect(error.serverInfo?.number == 942)  // Table or view doesn't exist
        }
    }

    @Test func returnBindOnTableWithUnfulfilledConstraintFails() async throws {
        do {
            let conn = try await OracleConnection.test(on: self.eventLoop)
            defer { #expect(throws: Never.self, performing: { try conn.syncClose() }) }

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
            Issue.record("Query with invalid constraint did not return an error, but it should have")
        } catch let error as OracleSQLError {
            #expect(error.serverInfo?.number == 2291)  // Constraint error
        }
    }

    @Test func connectionAttemptCancels() async {
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
        let eventLoop = eventLoop
        let cancelled = ManagedAtomic(false)
        let connect = Task {
            try await withTaskCancellationHandler {
                do {
                    let connection = try await OracleConnection.connect(
                        on: eventLoop,
                        configuration: configuration,
                        id: 1,
                        logger: .oracleTest
                    )
                    try await connection.close()
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    Issue.record("Unexpected error: \(String(reflecting: error))")
                }
            } onCancel: {
                cancelled.store(true, ordering: .relaxed)
            }
        }
        try? await Task.sleep(for: .seconds(8))  // should be in the second attempt
        connect.cancel()
        #expect(cancelled.load(ordering: .relaxed) == true)
    }

    @Test func plainQueryWorks() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { #expect(throws: Never.self, performing: { try conn.syncClose() }) }
        try await conn.execute("COMMIT")
    }

    @Test func earlyReturnAfterStreamCompleteDoesNotCrash() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { #expect(throws: Never.self, performing: { try conn.syncClose() }) }
        let stream = try await conn.execute("SELECT 1 FROM dual UNION ALL SELECT 2 FROM dual")
        for try await (id) in stream.decode(Int.self) {
            #expect(id == 1)
            break
        }
        try await Task.sleep(for: .seconds(0.5))
    }

    @Test func queryAfterCancellationDoesNotDeadlock() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { #expect(throws: Never.self, performing: { try conn.syncClose() }) }

        let rows = try await conn.execute(
            "SELECT to_number(column_value) AS id FROM xmltable ('1 to 10000')",
            logger: .oracleTest
        )
        var received: Int64 = 0
        for try await row in rows {
            var number: Int64?
            #expect(
                throws: Never.self,
                performing: { number = try row.decode(Int64.self, context: .default) }
            )
            received += 1
            #expect(number == received)
            if (number ?? 0) > 100 {
                break
            }
        }

        let rows2 = try await conn.execute("SELECT 'next_query' FROM dual", logger: .oracleTest)
        var received2 = 0
        for try await row in rows2 {
            #expect(try row.decode(String.self) == "next_query")
            received2 += 1
        }
        #expect(received2 == 1)
    }

    @Test func pendingTasksAreExecuted() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { #expect(throws: Never.self, performing: { try conn.syncClose() }) }

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

    @Test func storedProcedure() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { #expect(throws: Never.self, performing: { try conn.syncClose() }) }

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
        #expect(myCount == 13)
    }

    @Test func storedProcedureWithVarchar() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { #expect(throws: Never.self, performing: { try conn.syncClose() }) }

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
        #expect(myName == "DummyName")
    }

    @Test(.disabled(if: env("TEST_PRIVILEGED")?.isEmpty != false)) func domainAndAnnotations() async throws {
        let conn = try await OracleConnection.test(
            on: eventLoop, config: .privilegedTest()
        )
        defer { #expect(throws: Never.self, performing: { try conn.syncClose() }) }

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

    @Test func longBindBeforeNonLONGBindWorks() async throws {
        var buffer = ByteBuffer()
        buffer.reserveCapacity("binary data".utf8.count * 5000)
        for _ in 0..<5000 {
            buffer.writeString("binary data")
        }
        let conn = try await OracleConnection.test(on: eventLoop)
        defer { #expect(throws: Never.self, performing: { try conn.syncClose() }) }

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
            #expect(data == buffer)
            #expect(filename == "image.jpeg")
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
            #expect(data == buffer)
            #expect(filename == "image.jpeg")
        }
    }

    @Test func cursor() async throws {
        let conn = try await OracleConnection.test(on: eventLoop)
        defer { #expect(throws: Never.self, performing: { try conn.syncClose() }) }

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
        #expect(
            cursor.columns.map(\.name) == [
                "INPUT_VALUE", "DOUBLED_VALUE_STR", "ALPHABETS", "DOUBLED_VALUE", "INCREASED_VALUE",
            ]
        )
        let stream = try await cursor.execute(on: conn)
        var received = 0
        for try await _ in stream.decode((Int, String, String, Int, Int).self) {
            received += 1
        }
        #expect(received == 50)

        // Cannot be executed again
        var secondSucceeded = true
        do {
            _ = try await cursor.execute(on: conn)
        } catch {
            secondSucceeded = false
            let error = try #require(error as? OracleSQLError)
            #expect(error.code == .server)
            #expect(error.serverInfo?.number == 1001)  // unknown cursor id
        }
        #expect(secondSucceeded == false)
    }

    @Test func rowID() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { #expect(throws: Never.self, performing: { try conn.syncClose() }) }
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
            #expect(currentID == id)
            if currentID == 1 {
                firstRowID = rowID
            }
        }
        #expect(currentID == 50)
        let rowID = try #require(firstRowID)
        let singleRowStream =
            try await conn
            .execute("SELECT rowid, id FROM row_id_test WHERE rowid = \(rowID)")
        currentID = 0
        for try await (fetchedRowID, id) in singleRowStream.decode((String, Int).self) {
            currentID += 1
            #expect(id == 1)
            #expect(fetchedRowID == rowID.description)
        }
        #expect(currentID == 1)
    }

    @Test func unicode() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { #expect(throws: Never.self, performing: { try conn.syncClose() }) }
        let stream = try await conn.execute("SELECT 'ьми' AS col FROM dual")
        for try await (value) in stream.decode(String.self) {
            #expect(value == "ьми")
        }
    }

    @Test func long() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { #expect(throws: Never.self, performing: { try conn.syncClose() }) }
        do {
            try await conn.execute(
                "DROP TABLE tbl_long", logger: .oracleTest
            )
        } catch let error as OracleSQLError {
            // "ORA-00942: table or view does not exist" can be ignored
            #expect(error.serverInfo?.number == 942)
        }
        try await conn.execute(
            "CREATE TABLE tbl_long (id number, title long)",
            logger: .oracleTest
        )
        try await conn.execute(
            "INSERT INTO tbl_long (id, title) VALUES (1, 'hello!')",
            logger: .oracleTest
        )
        let stream = try await conn.execute("SELECT id, title FROM tbl_long")
        for try await (id, value) in stream.decode((Int, String).self) {
            #expect(id == 1)
            #expect(value == "hello!")
        }
    }

    @Test func listBind() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { #expect(throws: Never.self, performing: { try conn.syncClose() }) }
        do {
            try await conn.execute(
                "DROP TABLE sortable_ids", logger: .oracleTest
            )
        } catch let error as OracleSQLError {
            // "ORA-00942: table or view does not exist" can be ignored
            #expect(error.serverInfo?.number == 942)
        }
        try await conn.execute("CREATE TABLE sortable_ids (id NUMBER, sortorder NUMBER)")
        for i in 1...10 {
            try await conn.execute("INSERT INTO sortable_ids (id, sortorder) VALUES (\(OracleNumber(i)), 0)")
        }
        let shuffled = (1...10).shuffled()
        try await conn.execute(
            """
            DECLARE 
                TYPE id_array IS TABLE OF NUMBER;
                ids id_array := id_array(\(list: shuffled.map(OracleNumber.init)));
            BEGIN
                FOR i IN 1..ids.COUNT LOOP
                    UPDATE sortable_ids
                    SET sortorder = i
                    WHERE id = ids(i);
                END LOOP;

                COMMIT;
            END;
            """)
        print(shuffled)
        let stream = try await conn.execute("SELECT id, sortorder FROM sortable_ids")
        for try await (id, order) in stream.decode((Int, Int).self) {
            print(id, order)
        }
    }

    @Test func insertAboveCursorLimit() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { #expect(throws: Never.self, performing: { try conn.syncClose() }) }
        do {
            try await conn.execute(
                "DROP TABLE too_many_open_cursers", logger: .oracleTest
            )
        } catch let error as OracleSQLError {
            // "ORA-00942: table or view does not exist" can be ignored
            #expect(error.serverInfo?.number == 942)
        }
        try await conn.execute("CREATE TABLE too_many_open_cursers (id NUMBER)")
        for i in 1...1000 {
            try await conn.execute("INSERT INTO too_many_open_cursers (id) VALUES (\(OracleNumber(i)))")
        }
        let stream = try await conn.execute("SELECT id FROM too_many_open_cursers ORDER BY id")
        var num = 0
        for try await id in stream.decode(Int.self) {
            num += 1
            #expect(id == num)
        }
        #expect(num == 1000)
    }

    @Test(.bug(id: 86)) func rowIDFromInsertedRow() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { #expect(throws: Never.self, performing: { try conn.syncClose() }) }
        do {
            try await conn.execute("DROP TABLE get_row_id_86", logger: .oracleTest)
        } catch let error as OracleSQLError {
            #expect(error.serverInfo?.number == 942)
        }
        try await conn.execute("CREATE TABLE get_row_id_86 (id NUMBER)")
        let rowIDRef = OracleRef(dataType: .rowID, isReturnBind: true)
        let result = try await conn.execute(
            "INSERT INTO get_row_id_86 (id) VALUES (1) RETURNING rowid INTO \(rowIDRef)")
        #expect(try await result.affectedRows == 1)
        let rowID = try rowIDRef.decode(of: RowID.self)
        let id = try await conn.execute("SELECT id FROM get_row_id_86 WHERE rowid = \(rowID)").collect().first?
            .decode(Int.self)
        #expect(id == 1)
    }

    @Test(.bug(id: 86)) func getLastRowID() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { #expect(throws: Never.self, performing: { try conn.syncClose() }) }
        do {
            try await conn.execute("DROP TABLE get_row_id_86", logger: .oracleTest)
        } catch let error as OracleSQLError {
            #expect(error.serverInfo?.number == 942)
        }
        try await conn.execute("CREATE TABLE get_row_id_86 (id NUMBER)")
        let result = try await conn.execute(
            "INSERT INTO get_row_id_86 (id) VALUES (1)")
        #expect(try await result.affectedRows == 1)
        let rowID = try #require(try await result.lastRowID)
        let id = try await conn.execute("SELECT id FROM get_row_id_86 WHERE rowid = \(rowID)").collect().first?
            .decode(Int.self)
        #expect(id == 1)
    }

    @Test(.bug(id: 86)) func getLastRowIDEvenIfNil() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { #expect(throws: Never.self, performing: { try conn.syncClose() }) }
        do {
            try await conn.execute("DROP TABLE get_row_id_86_2", logger: .oracleTest)
        } catch let error as OracleSQLError {
            #expect(error.serverInfo?.number == 942)
        }
        try await conn.execute("CREATE TABLE get_row_id_86_2 (id NUMBER)")
        let result = try await conn.execute(
            "SELECT id FROM get_row_id_86_2")
        #expect(try await result.affectedRows == 0)
        #expect(try await result.lastRowID == nil)
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
