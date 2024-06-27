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

import NIOCore
import NIOPosix
import XCTest

@testable import OracleNIO

final class OracleRowStreamTests: XCTestCase {
    func testEmptyStream() {
        let stream = OracleRowStream(source: .noRows(.success(())))

        XCTAssertEqual(try stream.all().wait(), [])
    }

    func testAsyncEmptyStream() async throws {
        let stream = OracleRowStream(source: .noRows(.success(())))

        let rows = try await stream.asyncSequence().collect()
        XCTAssertEqual(rows, [])
    }

}
