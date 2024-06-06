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

import OracleNIO
import XCTest

final class OracleVectorTests: XCTestCase {
    func testVectorInt8() {
        var vector1 = OracleVectorInt8()
        XCTAssertEqual(vector1, [])
        vector1.reserveLanes(3)
        XCTAssertEqual(vector1, [0, 0, 0])
        let vector2: OracleVectorInt8 = [1, 2, 3]
        XCTAssertEqual(vector2.max(), 3)
        XCTAssertEqual(vector2.scalarCount, 3)
    }
}
