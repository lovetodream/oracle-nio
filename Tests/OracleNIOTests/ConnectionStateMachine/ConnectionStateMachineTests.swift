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

import NIOEmbedded
import XCTest

@testable import OracleNIO

final class ConnectionStateMachineTests: XCTestCase {
    func testQueuedTasksAreExecuted() throws {
        var state = ConnectionStateMachine(.readyForQuery)
        let promise1 = EmbeddedEventLoop().makePromise(of: Void.self)
        promise1.fail(OracleSQLError.uncleanShutdown)  // we don't care about the error at all.
        let promise2 = EmbeddedEventLoop().makePromise(of: Void.self)
        promise2.fail(OracleSQLError.uncleanShutdown)  // we don't care about the error at all.
        let success = OracleBackendMessage.Status(callStatus: 1, endToEndSequenceNumber: 0)

        XCTAssertEqual(state.enqueue(task: .ping(promise1)), .sendPing)
        XCTAssertEqual(state.enqueue(task: .ping(promise2)), .wait)
        XCTAssertEqual(state.statusReceived(success), .succeedPing(promise1))
        XCTAssertEqual(state.readyForQueryReceived(), .sendPing)
    }
}
