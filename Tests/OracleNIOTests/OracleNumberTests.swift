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

import Testing

import struct Foundation.Decimal

@testable import OracleNIO

@Suite struct OracleNumberTests {
    @Test func description() {
        #expect(OracleNumber(1.001).description == "1.001")
    }

    @Test func initializers() {
        #expect(OracleNumber("1.001") == 1.001)
        #expect(OracleNumber("hello") == nil)
        #expect(OracleNumber(Int(1)) == 1)
        #expect(OracleNumber(Float(1.0)) == 1.0)
        #expect(OracleNumber(Double(1.1)) == 1.1)
        #expect(OracleNumber(decimal: Decimal(1)) == 1)

        let integerLiteral: OracleNumber = 1
        #expect(integerLiteral == 1)
        let floatLiteral: OracleNumber = 1.0
        #expect(floatLiteral == 1.0)
    }
}
