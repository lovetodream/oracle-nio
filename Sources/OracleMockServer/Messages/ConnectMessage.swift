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

struct ConnectMessage: ServerMessage {
    func serialize() throws -> ByteBuffer {
        try ByteBuffer(
            plainHexEncodedBytes: """
                00 3D 00 00 02 00 00 00        
                01 3F 00 01 00 00 00 00
                01 00 00 00 00 3D C5 00
                00 00 00 00 00 00 00 00
                00 00 20 00 00 00 20 00
                00 12 00 00 00 74 99 CA
                F8 4C 3F 33 75 35 68 16
                09 63 2C D5 ED
                """)
    }
}
