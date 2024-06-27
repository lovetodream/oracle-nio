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

import struct NIOCore.ByteBuffer

extension ByteBuffer {
    mutating func writeQLocator(dataLength: UInt64) {
        self.writeUB4(40)  // QLocator length
        self.writeInteger(UInt8(40))  // chunk length
        self.writeInteger(UInt16(38))  // QLocator length is full - 2 bytes
        self.writeInteger(Constants.TNS_LOB_QLOCATOR_VERSION)
        self.writeInteger(
            Constants.TNS_LOB_LOCATOR_FLAGS_VALUE_BASED | Constants.TNS_LOB_LOCATOR_FLAGS_BLOB
                | Constants.TNS_LOB_LOCATOR_FLAGS_ABSTRACT
        )
        self.writeInteger(Constants.TNS_LOB_LOCATOR_FLAGS_INIT)
        self.writeInteger(UInt16(0))  // additional flags
        self.writeInteger(UInt16(1))  // byt1
        self.writeInteger(dataLength)
        self.writeInteger(UInt16(0))  // unused
        self.writeInteger(UInt16(0))  // csid
        self.writeInteger(UInt16(0))  // unused
        self.writeInteger(UInt64(0))  // unused
        self.writeInteger(UInt64(0))  // unused
    }
}
