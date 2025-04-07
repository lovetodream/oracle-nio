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

struct SelectManyFromDualMessage: ServerMessage {
    func serialize() throws -> ByteBuffer {
        try ByteBuffer(
            plainHexEncodedBytes: """
                00 00 00 B7 06 00 00 00
                20 00 10 17 7E 16 69 74
                E2 FB CF 90 76 16 A0 9F
                68 7E 01 AB 78 7D 04 07
                06 2B 04 01 16 01 01 82
                02 00 00 00 01 16 00 00
                00 00 00 00 00 00 01 02
                01 02 02 49 44 00 00 00
                00 00 00 00 00 00 00 01
                07 07 78 7D 04 07 06 2C
                15 00 02 1F E8 01 0A 01
                0A 00 06 22 01 01 00 01
                02 00 00 00 07 02 C1 02
                07 02 C1 03 08 01 06 03
                82 C8 64 00 01 01 00 00
                00 00 01 01 00 01 0B 0B
                80 00 00 00 3E 3C 3C 80
                00 00 00 01 A3 00 04 01
                01 01 7D 01 02 00 00 00
                01 01 00 03 00 00 00 00
                00 00 00 00 00 00 00 00
                03 00 01 01 00 00 00 00
                00 01 02 01 03 00 1D
                """)
    }
}
