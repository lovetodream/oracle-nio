import XCTest
@testable import OracleNIO
import NIOCore

final class OracleQueryContextTests: XCTestCase {

    func testStatementWithSpaceSeparator() {
        var context: ExtendedQueryContext?
        defer { context?.cleanup() }
        XCTAssertNoThrow(context = try ExtendedQueryContext(query: "SELECT any FROM any"))
        XCTAssertEqual(context?.statement.isQuery, true)
    }

    func testStatementWithNewlineSeparator() {
        var context: ExtendedQueryContext?
        defer { context?.cleanup() }
        XCTAssertNoThrow(context = try ExtendedQueryContext(query: """
        SELECT
        any,
        any2,
        any3
        FROM
        any
        """))
        XCTAssertEqual(context?.statement.isQuery, true)
    }

}

extension ExtendedQueryContext {
    
    convenience init(query: OracleQuery) throws {
        try self.init(
            query: query, options: .init(), useCharacterConversion: true,
            logger: .oracleTest,
            promise: OracleConnection.defaultEventLoopGroup.any().makePromise()
        )
    }

    func cleanup() {
        switch self.statement {
        case .query(let promise), .plsql(let promise), .dml(let promise), .ddl(let promise):
            promise.fail(TestComplete())
        }
    }

    struct TestComplete: Error { }

}
