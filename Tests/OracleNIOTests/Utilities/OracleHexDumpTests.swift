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

final class OracleHexDumpTests: XCTestCase {
    func testOracleDump() {
        let buffer = ByteBuffer(bytes: [
            0x0, 0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7,
            0x8, 0x9, 0xa, 0xb, 0xc, 0xd, 0xe, 0xf,
            UInt8(ascii: "a"),
        ])
        XCTAssertEqual(
            buffer.oracleHexDump(),
            """
            0000 : 00 01 02 03 04 05 06 07 |........|
            0008 : 08 09 0A 0B 0C 0D 0E 0F |........|
            0016 : 61                      |a       |

            """)
    }

    func testEmpty() {
        let buffer = ByteBuffer()
        XCTAssertEqual(buffer.oracleHexDump(), "")
    }
}
