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

#if compiler(>=6.0)
import NIOCore
import Testing

@testable import OracleNIO

@Suite struct StatementContextTests {

    @Test func statementWithSpaceSeparator() {
        let context = StatementContext(statement: "SELECT any FROM any")
        defer { context.cleanup() }
        #expect(context.type.isQuery)
    }

    @Test func statementWithNewlineSeparator() {
        let context = StatementContext(
            statement: """
                SELECT
                any,
                any2,
                any3
                FROM
                any
                """)
        defer { context.cleanup() }
        #expect(context.type.isQuery)
    }

    @Test func queryWithSingleLineComments() {
        let context = StatementContext(
            statement: """
                -- hello there
                SELECT any, any2,
                -- hello again
                any3 FROM any
                -- goodby
                """)
        defer { context.cleanup() }
        #expect(context.type.isQuery)
    }

    @Test func queryWithMultiLineComments() {
        let context = StatementContext(
            statement: """
                /* Hello there */
                SELECT any, any2,
                -- I'm sneaky
                /*
                Hello again,
                I'd like to tell you a tale!
                */
                any3 FROM any --bye
                """)
        defer { context.cleanup() }
        #expect(context.type.isQuery)
    }

}
#endif
