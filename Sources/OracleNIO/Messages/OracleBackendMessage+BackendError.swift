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

extension OracleBackendMessage {
    struct BackendError: PayloadDecodable, Hashable {
        var number: UInt32
        var cursorID: UInt16?
        var position: UInt16?
        var rowCount: UInt64?
        var isWarning: Bool
        var message: String?
        var rowID: RowID?
        var batchErrors: [OracleError]

        static func decodeWarning(
            from buffer: inout ByteBuffer,
            context: OracleBackendMessageDecoder.Context
        ) throws -> OracleBackendMessage.BackendError {
            let number = try buffer.throwingReadInteger(as: UInt16.self)
            // error number
            let length = try buffer.throwingReadInteger(as: UInt16.self)
            // length of error message
            buffer.moveReaderIndex(forwardBy: 2)  // skip flags
            let errorMessage: String?
            if number != 0 && length > 0 {
                errorMessage = buffer.readString(length: Int(length))
            } else {
                errorMessage = nil
            }
            return .init(
                number: UInt32(number),
                isWarning: true,
                message: errorMessage,
                batchErrors: []
            )
        }

        static func decode(
            from buffer: inout ByteBuffer,
            context: OracleBackendMessageDecoder.Context
        ) throws -> OracleBackendMessage.BackendError {
            _ = try buffer.throwingReadUB4()  // end of call status
            buffer.skipUB2()  // end to end seq#
            buffer.skipUB4()  // current row number
            buffer.skipUB2()  // error number
            buffer.skipUB2()  // array elem error
            buffer.skipUB2()  // array elem error
            let cursorID = buffer.readUB2()  // cursor id
            let errorPosition = buffer.readUB2()  // error position
            buffer.moveReaderIndex(forwardBy: 1)  // sql type
            buffer.moveReaderIndex(forwardBy: 1)  // fatal?
            buffer.moveReaderIndex(forwardBy: 1)  // flags
            buffer.moveReaderIndex(forwardBy: 1)  // user cursor options
            buffer.moveReaderIndex(forwardBy: 1)  // UDI parameter
            buffer.moveReaderIndex(forwardBy: 1)  // warning flag
            let rowID = try RowID(from: &buffer, type: .rowID, context: .default)
            buffer.skipUB4()  // OS error
            buffer.moveReaderIndex(forwardBy: 1)  // statement number
            buffer.moveReaderIndex(forwardBy: 1)  // call number
            buffer.skipUB2()  // padding
            buffer.skipUB4()  // success iters
            if let byteCount = buffer.readUB4(), byteCount > 0 {
                buffer.skipRawBytesChunked()  // oerrdd (logical rowid)
            }

            // batch error codes
            let numberOfCodes =
                try buffer.throwingReadUB2()  // batch error codes array
            var batch = [OracleError]()
            if numberOfCodes > 0 {
                let firstByte = try buffer.throwingReadInteger(as: UInt8.self)
                for _ in 0..<numberOfCodes {
                    if firstByte == Constants.TNS_LONG_LENGTH_INDICATOR {
                        buffer.skipUB4()  // chunk length ignored
                    }
                    let errorCode = try buffer.throwingReadUB2()
                    batch.append(.init(code: Int(errorCode)))
                }
                if firstByte == Constants.TNS_LONG_LENGTH_INDICATOR {
                    buffer.moveReaderIndex(forwardBy: 1)  // ignore end marker
                }
            }

            // batch error offsets
            let numberOfOffsets =
                try buffer.throwingReadUB2()  // batch error row offset array
            if numberOfOffsets > 0 {
                let firstByte = try buffer.throwingReadInteger(as: UInt8.self)
                for i in 0..<numberOfOffsets {
                    if firstByte == Constants.TNS_LONG_LENGTH_INDICATOR {
                        buffer.skipUB4()  // chunked length ignored
                    }
                    let offset = try buffer.throwingReadUB4()
                    batch[Int(i)].offset = Int(offset)
                }
                if firstByte == Constants.TNS_LONG_LENGTH_INDICATOR {
                    buffer.moveReaderIndex(forwardBy: 1)  // ignore end marker
                }
            }

            // batch error messages
            let numberOfMessages =
                try buffer.throwingReadUB2()  // batch error messages array
            if numberOfMessages > 0 {
                buffer.moveReaderIndex(forwardBy: 1)  // ignore packet size
                for i in 0..<numberOfMessages {
                    buffer.skipUB2()  // skip chunk length
                    let errorMessage =
                        try buffer
                        .readString()
                        .trimmingCharacters(in: .whitespaces)
                    batch[Int(i)].message = errorMessage
                    buffer.moveReaderIndex(forwardBy: 2)  // ignore end marker
                }
            }

            let number = try buffer.throwingReadUB4()
            let rowCount = buffer.readUB8()

            // fields added with 20c
            if context.capabilities.ttcFieldVersion >= Constants.TNS_CCAP_FIELD_VERSION_20_1 {
                buffer.skipUB4()  // sql type
                buffer.skipUB4()  // server checksum
            }

            let errorMessage: String?
            if number != 0 {
                errorMessage =
                    try buffer
                    .readString()
                    .trimmingCharacters(in: .whitespaces)
            } else {
                errorMessage = nil
            }

            return .init(
                number: number,
                cursorID: cursorID,
                position: errorPosition,
                rowCount: rowCount,
                isWarning: false,
                message: errorMessage,
                rowID: rowID,
                batchErrors: batch
            )
        }
    }
}
