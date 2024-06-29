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

@testable import OracleNIO

struct OracleFrontendMessageDecoder: NIOSingleStepByteToMessageDecoder {
    typealias InboundOut = OracleFrontendMessage

    private let headerSize = 8

    mutating func decode(buffer: inout ByteBuffer) throws -> OracleFrontendMessage? {
        // make sure we have at least one byte to read
        guard buffer.readableBytes > 0 else {
            return nil
        }

        let startReaderIndex = buffer.readerIndex
        let length =
            buffer
            .getInteger(at: startReaderIndex, as: UInt16.self) ?? 0

        guard buffer.readableBytes >= length else {
            return nil
        }

        let _ =
            buffer.getInteger(
                at: startReaderIndex + MemoryLayout<UInt32>.size + MemoryLayout<UInt8>.size,
                as: UInt8.self
            ) ?? 0  // packet flags

        guard
            let typeByte = buffer.getInteger(
                at: startReaderIndex + MemoryLayout<UInt32>.size,
                as: UInt8.self
            ),
            let type = PacketType(rawValue: typeByte)
        else {
            preconditionFailure("invalid packet")
        }

        // skip header
        buffer.moveReaderIndex(forwardBy: headerSize)

        switch type {
        case .connect:
            buffer.moveReaderIndex(forwardBy: buffer.readableBytes)
            return .connect
        case .data:
            let dataFlags = try buffer.throwingReadInteger(as: UInt16.self)
            if (dataFlags & Constants.TNS_DATA_FLAGS_EOF) != 0 {
                return .close
            }
            let messageIDByte = try buffer.throwingReadInteger(as: UInt8.self)
            let messageID = OracleFrontendMessageID(rawValue: messageIDByte)
            switch messageID {
            case .fastAuth:
                buffer.moveReaderIndex(forwardBy: buffer.readableBytes)
                return .fastAuth
            case .function:
                let functionCodeByte = try buffer.throwingReadInteger(as: UInt8.self)
                let functionCode = Constants.FunctionCode(rawValue: functionCodeByte)
                switch functionCode {
                case .authPhaseTwo:
                    buffer.moveReaderIndex(forwardBy: buffer.readableBytes)
                    return .authPhaseTwo
                case .logoff:
                    buffer.moveReaderIndex(forwardBy: buffer.readableBytes)
                    return .logoff
                default:
                    preconditionFailure("TODO: Unimplemented")
                }
            default:
                preconditionFailure("TODO: Unimplemented")
            }
        default:
            preconditionFailure("TODO: Unimplemented")
        }
    }

    mutating func decodeLast(buffer: inout ByteBuffer, seenEOF: Bool) throws
        -> OracleFrontendMessage?
    {
        try self.decode(buffer: &buffer)
    }
}

extension OracleFrontendMessage {

    static func decode(from buffer: inout ByteBuffer, for messageID: OracleFrontendMessageID) throws
        -> OracleFrontendMessage
    {
        switch messageID {
        default:
            preconditionFailure("TODO: Unimplemented")
        }
    }
}
