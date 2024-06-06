//===----------------------------------------------------------------------===//
//
// This source file is part of the OracleNIO open source project
//
// Copyright (c) 2024 Timo Zacherl and the OracleNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIOCore

@testable import OracleNIO

struct OracleBackendMessageEncoder: MessageToByteEncoder {
    typealias OutboundIn = OracleBackendMessageDecoder.Container

    var protocolVersion: Int

    func encode(data container: OutboundIn, out: inout ByteBuffer) {
        for message in container.messages {
            switch message {
            case .accept(let accept):
                self.encode(
                    id: .accept,
                    flags: container.flags,
                    payload: accept,
                    out: &out
                )
            default:
                fatalError("Not implemented")
            }
        }
    }

    func encode<P: OracleMessagePayloadEncodable>(
        id: OracleBackendMessage.ID,
        flags: UInt8,
        payload: P,
        out: inout ByteBuffer
    ) {
        let startIndex = out.writerIndex
        // length placeholder
        if self.protocolVersion >= Constants.TNS_VERSION_MIN_LARGE_SDU {
            out.writeInteger(0, as: UInt32.self)
        } else {
            out.writeInteger(0, as: UInt16.self)
            out.writeInteger(0, as: UInt16.self)
        }

        out.writeInteger(id.rawValue, as: UInt8.self)
        out.writeInteger(flags, as: UInt8.self)
        out.writeInteger(0, as: UInt16.self)  // remaining header part
        payload.encode(into: &out)

        if self.protocolVersion >= Constants.TNS_VERSION_MIN_LARGE_SDU {
            out.setInteger(UInt32(out.readableBytes - startIndex), at: startIndex, as: UInt32.self)
        } else {
            out.setInteger(UInt16(out.readableBytes - startIndex), at: startIndex, as: UInt16.self)
        }
    }
}

extension OracleBackendMessage.Accept: OracleMessagePayloadEncodable {
    func encode(into buffer: inout ByteBuffer) {
        buffer.writeInteger(self.newCapabilities.protocolVersion, as: UInt16.self)
        buffer.writeInteger(self.newCapabilities.protocolOptions, as: UInt16.self)
        buffer.writeBytes(Array(repeating: UInt8(0), count: 20))  // random chunk
        buffer.writeInteger(self.newCapabilities.sdu, as: UInt32.self)
        if self.newCapabilities.protocolVersion >= Constants.TNS_VERSION_MIN_OOB_CHECK {
            buffer.writeBytes(Array(repeating: UInt8(0), count: 5))  // more chunk
            if self.newCapabilities.supportsFastAuth {
                buffer.writeInteger(Constants.TNS_ACCEPT_FLAG_FAST_AUTH, as: UInt32.self)
            } else {
                buffer.writeInteger(0, as: UInt32.self)
            }
        }
    }
}

protocol OracleMessagePayloadEncodable {
    func encode(into buffer: inout ByteBuffer)
}
