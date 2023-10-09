import XCTest
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
        XCTAssertNoThrow(try conn.close().wait())
    }

    func testAuthenticationFailure() throws {
        let config = OracleConnection.Configuration(
            host: env("ORA_HOSTNAME") ?? "192.168.1.24",
            port: env("ORA_PORT").flatMap(Int.init) ?? 1521,
            service: .serviceName(env("ORA_SERVICE_NAME") ?? "XEPDB1"),
            username: env("ORA_USERNAME") ?? "my_user",
            password: "wrong_password"
        )

        var conn: OracleConnection?
        XCTAssertThrowsError(
            conn = try OracleConnection.connect(
                configuration: config, id: 1, logger: .oracleTest
            ).wait()
        ) {
            XCTAssertTrue($0 is OracleSQLError)
        }

        // In case of a test failure the connection must be closed.
        XCTAssertNoThrow(try conn?.close().wait())
    }

    func testSimpleQuery() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { XCTAssertNoThrow(try conn.close().wait()) }
        let rows = try await conn.query(
            "SELECT 'test' FROM dual", logger: .oracleTest
        ).collect()
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(try rows.first?.decode(String.self), "test")
    }

    func testSimpleDateQuery() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { XCTAssertNoThrow(try conn.close().wait()) }
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
        defer { XCTAssertNoThrow(try conn.close().wait()) }
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
        defer { XCTAssertNoThrow(try conn.close().wait()) }

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
        defer { XCTAssertNoThrow(try conn.close().wait()) }

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
        defer { XCTAssertNoThrow(try conn.close().wait()) }
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
        defer { XCTAssertNoThrow(try conn.close().wait()) }
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
        defer { XCTAssertNoThrow(try conn.close().wait()) }
        let rows = try await conn.query(
            "SELECT null FROM dual where rownum = 0", logger: .oracleTest
        ).collect()
        XCTAssertEqual(rows.count, 0)
    }

    func testNoRowsQueryFromActual() async throws {
        let conn = try await OracleConnection.test(on: self.eventLoop)
        defer { XCTAssertNoThrow(try conn.close().wait()) }
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
        defer { XCTAssertNoThrow(try conn.close().wait()) }
        XCTAssertNoThrow(try conn.ping().wait())
    }

    func testCommit() async throws {
        let conn1 = try await OracleConnection.test(on: self.eventLoop)
        let conn2 = try await OracleConnection.test(on: self.eventLoop)
        defer { XCTAssertNoThrow(try conn1.close().wait()) }
        defer { XCTAssertNoThrow(try conn2.close().wait()) }
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
        defer { XCTAssertNoThrow(try conn.close().wait()) }
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
        defer { XCTAssertNoThrow(try conn.close().wait()) }
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
        defer { XCTAssertNoThrow(try conn.close().wait()) }
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

    func testSimplePlSQL() async {
        do {
            let conn = try await OracleConnection.test(on: self.eventLoop)
            defer { XCTAssertNoThrow(try conn.close().wait()) }

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
            defer { XCTAssertNoThrow(try conn.close().wait()) }

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
            defer { XCTAssertNoThrow(try conn.close().wait()) }

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

}

let isLoggingConfigured: Bool = {
    LoggingSystem.bootstrap { label in
        var handler = StreamLogHandler.standardOutput(label: label)
        handler.logLevel = Logger.getLogLevel()
        return handler
    }
    return true
}()
