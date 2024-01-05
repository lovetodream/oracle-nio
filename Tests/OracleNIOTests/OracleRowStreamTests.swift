import NIOCore
import NIOEmbedded
import NIOPosix
import XCTest
@testable import OracleNIO

final class OracleRowStreamTests: XCTestCase {
    let eventLoop = EmbeddedEventLoop()

    func testEmptyStream() {
        let stream = OracleRowStream(
            source: .noRows(.success(())),
            eventLoop: self.eventLoop,
            logger: .oracleTest
        )

        XCTAssertEqual(try stream.all().wait(), [])
    }

    func testAsyncEmptyStream() async throws {
        let stream = OracleRowStream(
            source: .noRows(.success(())),
            eventLoop: self.eventLoop,
            logger: .oracleTest
        )

        let rows = try await stream.asyncSequence().collect()
        XCTAssertEqual(rows, [])
    }

}
