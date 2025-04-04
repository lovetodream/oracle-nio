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

struct CloseMessage: ServerMessage {
    func serialize() throws -> ByteBuffer {
        try ByteBuffer(
            plainHexEncodedBytes: """
                00 00 00 0F 06 00 00 00
                20 00 09 01 01 00 1D
                """)
    }
}
