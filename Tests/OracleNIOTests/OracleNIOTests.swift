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

    func testConnectionAndClose() {
        var conn: OracleConnection?
        XCTAssertNoThrow(conn = try OracleConnection.test(on: eventLoop).wait())
        XCTAssertNoThrow(try conn?.close().wait())
    }

    func testAuthenticationFailure() throws {
        let config = OracleConnection.Configuration(
            address: try OracleConnection.address(),
            serviceName: env("ORA_SERVICE_NAME") ?? "XEPDB1",
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

    func testSimpleQuery() {
        var conn: OracleConnection?
        XCTAssertNoThrow(conn = try OracleConnection.test(on: eventLoop).wait())
        defer { XCTAssertNoThrow(try conn?.close().wait()) }
        var rows: [OracleRow]?
        XCTAssertNoThrow(
            rows = try conn?.query(
                "SELECT 'test' FROM dual", logger: .oracleTest
            ).wait().rows
        )
        XCTAssertEqual(rows?.count, 1)
        XCTAssertEqual(try rows?.first?.decode(String.self), "test")
    }

    func testQuery10kItems() {
        var conn: OracleConnection?
        XCTAssertNoThrow(conn = try OracleConnection.test(on: eventLoop).wait())
        defer { XCTAssertNoThrow(try conn?.close().wait()) }

        var received: Int64 = 0
        XCTAssertNoThrow(_ = try conn?.query(
            "SELECT to_number(column_value) AS id FROM xmltable ('1 to 10000')",
            options: .init(arraySize: 500),
            logger: .oracleTest
        ) { row in
            func workaround() {
                var number: Int64?
                XCTAssertNoThrow(
                    number = try row.decode(Int64.self, context: .default)
                )
                received += 1
                XCTAssertEqual(number, received)
            }

            workaround()
        }.wait())

        XCTAssertEqual(received, 10_000)
    }

    func testFloatingPointNumbers() {
        var conn: OracleConnection?
        XCTAssertNoThrow(conn = try OracleConnection.test(on: eventLoop).wait())
        defer { XCTAssertNoThrow(try conn?.close().wait()) }

        var received: Int64 = 0
        XCTAssertNoThrow(_ = try conn?.query(
            """
            SELECT to_number(column_value) / 100 AS id 
            FROM xmltable ('1 to 100')
            """,
            logger: .oracleTest
        ) { row in
            func workaround() {
                var number: Float?
                XCTAssertNoThrow(number = try row.decode(
                    Float.self, context: .default)
                )
                received += 1
                XCTAssertEqual(number, (Float(received) / 100))
            }

            workaround()
        }.wait())

        XCTAssertEqual(received, 100)
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
