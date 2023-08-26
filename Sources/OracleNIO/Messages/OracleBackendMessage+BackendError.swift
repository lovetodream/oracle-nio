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
            from buffer: inout ByteBuffer, capabilities: Capabilities
        ) throws -> OracleBackendMessage.BackendError {
            let number = try buffer.throwingReadInteger(as: UInt16.self)
                // error number
            let length = try buffer.throwingReadInteger(as: UInt16.self)
                // length of error message
            buffer.moveReaderIndex(forwardBy: 2) // skip flags
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
            from buffer: inout ByteBuffer, capabilities: Capabilities
        ) throws -> OracleBackendMessage.BackendError {
            _ = try buffer.throwingReadUB4() // end of call status
            buffer.skipUB2() // end to end seq#
            buffer.skipUB4() // current row number
            buffer.skipUB2() // error number
            buffer.skipUB2() // array elem error
            buffer.skipUB2() // array elem error
            let cursorID = buffer.readUB2() // cursor id
            let errorPosition = buffer.readUB2() // error position
            buffer.skipUB1() // sql type
            buffer.skipUB1() // fatal?
            buffer.skipUB2() // flags
            buffer.skipUB2() // user cursor options
            buffer.skipUB1() // UDI parameter
            buffer.skipUB1() // warning flag
            let rowID = RowID(from: &buffer)
            buffer.skipUB4() // OS error
            buffer.skipUB1() // statement number
            buffer.skipUB1() // call number
            buffer.skipUB2() // padding
            buffer.skipUB4() // success iters
            if let byteCount = buffer.readUB4(), byteCount > 0 {
                buffer.skipRawBytesChunked()
            }

            // batch error codes
            let numberOfCodes =
                try buffer.throwingReadUB2() // batch error codes array
            var batch = [OracleError]()
            if numberOfCodes > 0 {
                let firstByte = try buffer.throwingReadInteger(as: UInt8.self)
                for _ in 0..<numberOfCodes {
                    if firstByte == Constants.TNS_LONG_LENGTH_INDICATOR {
                        buffer.skipUB4() // chunk length ignored
                    }
                    let errorCode = try buffer.throwingReadUB2()
                    batch.append(.init(code: Int(errorCode)))
                }
                if firstByte == Constants.TNS_LONG_LENGTH_INDICATOR {
                    buffer.moveReaderIndex(forwardBy: 1) // ignore end marker
                }
            }

            // batch error offsets
            let numberOfOffsets =
                try buffer.throwingReadUB2() // batch error row offset array
            if numberOfOffsets > 0 {
                let firstByte = try buffer.throwingReadInteger(as: UInt8.self)
                for i in 0..<numberOfOffsets {
                    if firstByte == Constants.TNS_LONG_LENGTH_INDICATOR {
                        buffer.skipUB4() // chunked length ignored
                    }
                    let offset = try buffer.throwingReadUB4()
                    batch[Int(i)].offset = Int(offset)
                }
                if firstByte == Constants.TNS_LONG_LENGTH_INDICATOR {
                    buffer.moveReaderIndex(forwardBy: 1) // ignore end marker
                }
            }

            // batch error messages
            let numberOfMessages =
                try buffer.throwingReadUB2() // batch error messages array
            if numberOfMessages > 0 {
                buffer.moveReaderIndex(forwardBy: 1) // ignore packet size
                for i in 0..<numberOfMessages {
                    buffer.skipUB2() // skip chunk length
                    let errorMessage = buffer
                        .readString(with: Constants.TNS_CS_IMPLICIT)?
                        .trimmingCharacters(in: .whitespaces)
                    batch[Int(i)].message = errorMessage
                    buffer.moveReaderIndex(forwardBy: 2) // ignore end marker
                }
            }

            let number = try buffer.throwingReadUB4()
            let rowCount = buffer.readUB8()
            let errorMessage: String?
            if number != 0 {
                errorMessage = buffer
                    .readString(with: Constants.TNS_CS_IMPLICIT)?
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
