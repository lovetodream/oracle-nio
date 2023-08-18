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

}

let isLoggingConfigured: Bool = {
    LoggingSystem.bootstrap { label in
        var handler = StreamLogHandler.standardOutput(label: label)
        handler.logLevel = Logger.getLogLevel()
        return handler
    }
    return true
}()
