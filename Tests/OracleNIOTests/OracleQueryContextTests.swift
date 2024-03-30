// Copyright 2024 Timo Zacherl
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OracleNIO
import NIOCore

final class OracleQueryContextTests: XCTestCase {

    func testStatementWithSpaceSeparator() {
        var context: ExtendedQueryContext?
        defer { context?.cleanup() }
        XCTAssertNoThrow(context = ExtendedQueryContext(query: "SELECT any FROM any"))
        XCTAssertEqual(context?.statement.isQuery, true)
    }

    func testStatementWithNewlineSeparator() {
        var context: ExtendedQueryContext?
        defer { context?.cleanup() }
        XCTAssertNoThrow(context = ExtendedQueryContext(query: """
        SELECT
        any,
        any2,
        any3
        FROM
        any
        """))
        XCTAssertEqual(context?.statement.isQuery, true)
    }

    func testQueryWithSingleLineComments() {
        var context: ExtendedQueryContext?
        defer { context?.cleanup() }
        XCTAssertNoThrow(context = ExtendedQueryContext(query: """
        -- hello there
        SELECT any, any2,
        -- hello again
        any3 FROM any
        -- goodby
        """))
        XCTAssertEqual(context?.statement.isQuery, true)
    }

    func testQueryWithMultiLineComments() {
        var context: ExtendedQueryContext?
        defer { context?.cleanup() }
        XCTAssertNoThrow(context = ExtendedQueryContext(query: """
        /* Hello there */
        SELECT any, any2,
        -- I'm sneaky
        /*
        Hello again,
        I'd like to tell you a tale!
        */
        any3 FROM any --bye
        """))
        XCTAssertEqual(context?.statement.isQuery, true)
    }

}

extension ExtendedQueryContext {
    
    convenience init(query: OracleQuery) {
        self.init(
            query: query, options: .init(),
            logger: .oracleTest,
            promise: OracleConnection.defaultEventLoopGroup.any().makePromise()
        )
    }

    func cleanup() {
        switch self.statement {
        case .query(let promise), 
             .plsql(let promise),
             .dml(let promise),
             .ddl(let promise),
             .plain(let promise):
            promise.fail(TestComplete())
        }
    }

    struct TestComplete: Error { }

}
