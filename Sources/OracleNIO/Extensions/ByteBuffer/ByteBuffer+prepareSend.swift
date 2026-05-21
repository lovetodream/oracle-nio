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

extension ByteBuffer {
    mutating func prepareSend(
        packetType: PacketType,
        packetFlags: UInt8 = 0,
        protocolVersion: UInt16
    ) {
        self.prepareSend(
            packetTypeByte: packetType.rawValue,
            packetFlags: packetFlags,
            protocolVersion: protocolVersion
        )
    }

    mutating func prepareSend(
        packetTypeByte: UInt8,
        packetFlags: UInt8 = 0,
        protocolVersion: UInt16
    ) {
        var position = 0
        if protocolVersion >= Constants.TNS_VERSION_MIN_LARGE_SDU {
            self.setInteger(UInt32(self.readableBytes), at: position)
            position += MemoryLayout<UInt32>.size
        } else {
            self.setInteger(UInt16(self.readableBytes), at: position)
            position += MemoryLayout<UInt16>.size
            self.setInteger(UInt16(0), at: position)
            position += MemoryLayout<UInt16>.size
        }
        self.setInteger(packetTypeByte, at: position)
        position += MemoryLayout<UInt8>.size
        self.setInteger(packetFlags, at: position)
        position += MemoryLayout<UInt8>.size
        self.setInteger(UInt16(0), at: position)
        position += MemoryLayout<UInt16>.size
    }
}
