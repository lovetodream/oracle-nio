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

extension ExtendedQueryContext {

    convenience init(
        query: OracleQuery,
        promise: EventLoopPromise<OracleRowStream> = EmbeddedEventLoop().makePromise()
    ) {
        self.init(
            query: query, options: .init(),
            logger: OracleConnection.noopLogger,
            promise: promise
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

    struct TestComplete: Error {}

}
