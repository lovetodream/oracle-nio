//===----------------------------------------------------------------------===//
//
// This source file is part of the OracleNIO open source project
//
// Copyright (c) 2025 Timo Zacherl and the OracleNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
// See CONTRIBUTORS.md for the list of OracleNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIOCore

struct SelectOneFromDualMessage: ServerMessage {
    func serialize() throws -> ByteBuffer {
        try ByteBuffer(
            plainHexEncodedBytes: """
                00 00 00 DE 06 00 00 00
                20 00 10 17 F2 4A 5B D1
                F8 17 43 6E 62 9C F3 5B
                42 EF B2 4B 78 7D 04 03
                07 2B 25 01 05 01 01 82
                60 80 00 00 01 05 00 00
                00 00 02 03 69 01 01 05
                02 3F FE 01 07 01 07 07
                27 48 45 4C 4C 4F 27 00
                00 00 00 00 00 00 00 00
                00 01 07 07 78 7D 04 03
                07 2C 08 00 02 1F E8 01
                02 01 02 00 06 22 01 01
                00 01 02 00 00 00 07 05
                68 65 6C 6C 6F 08 01 06
                03 6F A6 F4 00 01 01 00
                00 00 00 01 01 00 01 0B
                0B 80 00 00 00 3E 3C 3C
                80 00 00 00 01 A3 00 04
                01 01 01 86 01 01 02 05
                7B 00 00 01 01 00 03 00
                00 00 00 00 00 00 00 00
                00 00 00 03 00 01 01 00
                00 00 00 02 05 7B 01 01
                01 03 00 19 4F 52 41 2D
                30 31 34 30 33 3A 20 6E
                6F 20 64 61 74 61 20 66
                6F 75 6E 64 0A 1D
                """)
    }
}
