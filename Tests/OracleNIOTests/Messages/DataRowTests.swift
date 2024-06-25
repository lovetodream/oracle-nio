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
import XCTest

@testable import OracleNIO

final class DataRowTests: XCTestCase {
    func testColumnWithNullIndicator() {
        let buffer = ByteBuffer(bytes: [Constants.TNS_NULL_LENGTH_INDICATOR])
        let row = DataRow(columnCount: 1, bytes: buffer)
        for column in row {
            XCTAssertEqual(column, .none)
        }
    }
}
