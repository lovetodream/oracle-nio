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

    @Suite struct OracleHexDumpTests {
        @Test func oracleDump() {
            let buffer = ByteBuffer(bytes: [
                0x0, 0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7,
                0x8, 0x9, 0xa, 0xb, 0xc, 0xd, 0xe, 0xf,
                UInt8(ascii: "a"),
            ])
            #expect(
                buffer.oracleHexDump() == """
                    0000 : 00 01 02 03 04 05 06 07 |........|
                    0008 : 08 09 0A 0B 0C 0D 0E 0F |........|
                    0016 : 61                      |a       |

                    """)
        }

        @Test func empty() {
            let buffer = ByteBuffer()
            #expect(buffer.oracleHexDump() == "")
        }

        @Test func stringInitializationIsTruncatedIfNeeded() {
            #expect(String(10_000, radix: 10, padding: 4) == "0000")
        }
    }
#endif
