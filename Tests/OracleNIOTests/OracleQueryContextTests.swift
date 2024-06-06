//===----------------------------------------------------------------------===//
//
// This source file is part of the OracleNIO open source project
//
// Copyright (c) 2024 Timo Zacherl and the OracleNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIOCore
import XCTest

@testable import OracleNIO

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
        XCTAssertNoThrow(
            context = ExtendedQueryContext(
                query: """
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
        XCTAssertNoThrow(
            context = ExtendedQueryContext(
                query: """
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
        XCTAssertNoThrow(
            context = ExtendedQueryContext(
                query: """
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
