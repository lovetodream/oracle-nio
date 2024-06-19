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

final class StatementContextTests: XCTestCase {

    func testStatementWithSpaceSeparator() {
        var context: StatementContext?
        defer { context?.cleanup() }
        XCTAssertNoThrow(
            context = StatementContext(
                statement: "SELECT any FROM any")
        )
        XCTAssertEqual(context?.type.isQuery, true)
    }

    func testStatementWithNewlineSeparator() {
        var context: StatementContext?
        defer { context?.cleanup() }
        XCTAssertNoThrow(
            context = StatementContext(
                statement: """
                    SELECT
                    any,
                    any2,
                    any3
                    FROM
                    any
                    """))
        XCTAssertEqual(context?.type.isQuery, true)
    }

    func testQueryWithSingleLineComments() {
        var context: StatementContext?
        defer { context?.cleanup() }
        XCTAssertNoThrow(
            context = StatementContext(
                statement: """
                    -- hello there
                    SELECT any, any2,
                    -- hello again
                    any3 FROM any
                    -- goodby
                    """))
        XCTAssertEqual(context?.type.isQuery, true)
    }

    func testQueryWithMultiLineComments() {
        var context: StatementContext?
        defer { context?.cleanup() }
        XCTAssertNoThrow(
            context = StatementContext(
                statement: """
                    /* Hello there */
                    SELECT any, any2,
                    -- I'm sneaky
                    /*
                    Hello again,
                    I'd like to tell you a tale!
                    */
                    any3 FROM any --bye
                    """))
        XCTAssertEqual(context?.type.isQuery, true)
    }

}
