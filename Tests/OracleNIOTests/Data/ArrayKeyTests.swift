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
    import Testing

    @testable import OracleNIO

    @Suite struct ArrayKeyTests {
        @Test func testInitWithInteger() {
            let key = ArrayKey(intValue: 2)!
            #expect(key.stringValue == "Index 2")
        }

        @Test func testInitWithIndex() {
            let key = ArrayKey(index: 12)
            #expect(key.stringValue == "Index 12")
        }

        @Test func testEquatable() {
            #expect(ArrayKey(index: 3) == ArrayKey(intValue: 3))
        }
    }
#endif
