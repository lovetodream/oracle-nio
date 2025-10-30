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

#if canImport(FoundationEssentials)
    import FoundationEssentials
#else
    import Foundation
#endif

@usableFromInline
struct BackendError: OracleBackendMessage.PayloadDecodable, Hashable, Sendable {
    @usableFromInline
    var number: UInt32
    var cursorID: UInt16?
    var position: UInt16?
    @usableFromInline
    var rowCount: Int
    var isWarning: Bool
    @usableFromInline
    var message: String?
    var rowID: RowID?
    var batchErrors: [OracleError]

    static func decodeWarning(
        from buffer: inout ByteBuffer,
        context: OracleBackendMessageDecoder.Context
    ) throws -> BackendError {
        let number = try buffer.throwingReadInteger(as: UInt16.self)
        // error number
        let length = try buffer.throwingReadInteger(as: UInt16.self)
        // length of error message
        try buffer.throwingMoveReaderIndex(forwardBy: 2)  // skip flags
        let errorMessage: String? =
            if number != 0 && length > 0 {
                try buffer.throwingReadString(length: Int(length)).replacing(/(^\s+|\s+$)/, with: "")
            } else {
                nil
            }
        return .init(
            number: UInt32(number),
            rowCount: 0,
            isWarning: true,
            message: errorMessage,
            batchErrors: []
        )
    }

    static func decode(
        from buffer: inout ByteBuffer,
        context: OracleBackendMessageDecoder.Context
    ) throws -> BackendError {
        try buffer.throwingSkipUB4()  // end of call status
        try buffer.throwingSkipUB2()  // end to end seq#
        try buffer.throwingSkipUB4()  // current row number
        try buffer.throwingSkipUB2()  // error number
        try buffer.throwingSkipUB2()  // array elem error
        try buffer.throwingSkipUB2()  // array elem error
        let cursorID = try buffer.throwingReadUB2()  // cursor id
        let errorPosition = try buffer.throwingReadUB2()  // error position
        try buffer.throwingSkipUB1()  // sql type
        try buffer.throwingSkipUB1()  // fatal?
        try buffer.throwingSkipUB1()  // flags
        try buffer.throwingSkipUB1()  // user cursor options
        try buffer.throwingSkipUB1()  // UDI parameter
        try buffer.throwingSkipUB1()  // warning flag
        let rowID = try RowID(fromWire: &buffer)
        try buffer.throwingSkipUB4()  // OS error
        try buffer.throwingSkipUB1()  // statement number
        try buffer.throwingSkipUB1()  // call number
        try buffer.throwingSkipUB2()  // padding
        try buffer.throwingSkipUB4()  // success iters
        let byteCount = try buffer.throwingReadUB4()
        if byteCount > 0 {
            buffer.skipRawBytesChunked()  // oerrdd (logical rowid)
        }

        // batch error codes
        let numberOfCodes = try buffer.throwingReadUB2()  // batch error codes array
        var batch = [OracleError]()
        if numberOfCodes > 0 {
            let firstByte = try buffer.throwingReadInteger(as: UInt8.self)
            for _ in 0..<numberOfCodes {
                if firstByte == Constants.TNS_LONG_LENGTH_INDICATOR {
                    try buffer.throwingSkipUB4()  // chunk length ignored
                }
                let errorCode = try buffer.throwingReadUB2()
                batch.append(.init(code: Int(errorCode)))
            }
            if firstByte == Constants.TNS_LONG_LENGTH_INDICATOR {
                try buffer.throwingSkipUB1()  // ignore end marker
            }
        }

        // batch error offsets
        let numberOfOffsets = try buffer.throwingReadUB2()  // batch error row offset array
        if numberOfOffsets > 0 {
            let firstByte = try buffer.throwingReadInteger(as: UInt8.self)
            for i in 0..<numberOfOffsets {
                if firstByte == Constants.TNS_LONG_LENGTH_INDICATOR {
                    try buffer.throwingSkipUB4()  // chunked length ignored
                }
                let offset = try buffer.throwingReadUB4()
                batch[Int(i)].offset = Int(offset)
            }
            if firstByte == Constants.TNS_LONG_LENGTH_INDICATOR {
                try buffer.throwingSkipUB1()  // ignore end marker
            }
        }

        // batch error messages
        let numberOfMessages = try buffer.throwingReadUB2()  // batch error messages array
        if numberOfMessages > 0 {
            try buffer.throwingSkipUB1()  // ignore packet size
            for i in 0..<numberOfMessages {
                try buffer.throwingSkipUB2()  // skip chunk length
                let errorMessage =
                    try buffer
                    .readString()
                    .replacing(/(^\s+|\s+$)/, with: "")
                batch[Int(i)].message = errorMessage
                try buffer.throwingMoveReaderIndex(forwardBy: 2)  // ignore end marker
            }
        }

        let number = try buffer.throwingReadUB4()
        let rowCount = try buffer.throwingReadUB8()

        // fields added with 20c
        if context.capabilities.ttcFieldVersion >= Constants.TNS_CCAP_FIELD_VERSION_20_1 {
            try buffer.throwingSkipUB4()  // sql type
            try buffer.throwingSkipUB4()  // server checksum
        }

        let errorMessage: String? =
            if number != 0 {
                try buffer.readString().replacing(/(^\s+|\s+$)/, with: "")
            } else {
                nil
            }

        return .init(
            number: number,
            cursorID: cursorID,
            position: errorPosition,
            rowCount: numericCast(rowCount),
            isWarning: false,
            message: errorMessage,
            rowID: rowID,
            batchErrors: batch
        )
    }
}
