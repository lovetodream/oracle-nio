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
import NIOEmbedded

@testable import OracleNIO

extension StatementContext {

    convenience init(
        statement: OracleStatement,
        promise: EventLoopPromise<OracleRowStream> = EmbeddedEventLoop().makePromise()
    ) {
        self.init(
            statement: statement, options: .init(),
            logger: OracleConnection.noopLogger,
            promise: promise
        )
    }

    func cleanup() {
        switch self.type {
        case .query(let promise),
            .plsql(let promise),
            .dml(let promise),
            .ddl(let promise),
            .cursor(_, let promise),
            .plain(let promise):
            promise.fail(TestComplete())
        }
    }

    struct TestComplete: Error {}

}
