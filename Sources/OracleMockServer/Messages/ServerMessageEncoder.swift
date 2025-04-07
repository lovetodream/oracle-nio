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

@available(macOS 14.0, *)
struct ServerMessageEncoder {
    static let headerSize = 8

    private let numberMaxDigits = 40
    private let numberAsSingleChars = 172

    private enum State {
        case flushed
        case writable
    }

    private var buffer: ByteBuffer
    private var state: State = .writable

    private var sequenceNumber: UInt8 = 0

    init(buffer: ByteBuffer) {
        self.buffer = buffer
    }

    mutating func flush() -> ByteBuffer {
        self.state = .flushed
        return self.buffer
    }

    mutating func rows(data: [Int], lastRowCount: Int, cursorID: UInt16 = 1, hasMoreRows: Bool = false) {
        self.clearIfNeeded()

        self.startRequest(packetType: .data(flags: 0x2000, .rowHeader))

        for row in data {
            self.rowHeader()
            self.rowData(value: row)
        }

        self.error(
            number: hasMoreRows ? 0 : 1403,
            cursorID: cursorID,
            rowCount: numericCast(lastRowCount + data.count)
        )

        self.endRequest(packetType: .data(flags: 0x2000, .rowData))
    }

    mutating func rowHeader(bitVector: [UInt8]? = nil) {
        buffer.writeInteger(OracleMockServer.MessageID.rowHeader.rawValue)
        buffer.writeInteger(UInt8(0))  // flags
        buffer.writeInteger(UInt8(0))  // number of requests
        buffer.writeInteger(UInt8(0))  // iteration number
        buffer.writeInteger(UInt8(0))  // number of iterations
        buffer.writeInteger(UInt8(0))  // buffer length
        if let bitVector {
            buffer.writeUB4(UInt32(bitVector.count))
            buffer.writeInteger(UInt8(0))  // skip repeated length
            buffer.writeBytes(bitVector)
        } else {
            buffer.writeInteger(UInt8(0))
        }
        buffer.writeInteger(UInt8(0))  // rxhrid
    }

    /// Currently we only allow rows of one value of type OracleNumber.
    ///
    /// It is enough for the benchmarks we are running. Support can be expanded in the future.
    /// - Parameter value: The column value
    mutating func rowData(value: Int) {
        buffer.writeInteger(OracleMockServer.MessageID.rowData.rawValue)
        encodeOracleNumberWithLength(value, into: &buffer)
    }

    mutating func error(
        number: UInt32,
        cursorID: UInt16,
        position: UInt16 = 0,
        rowCount: UInt64,
        isWarning: Bool = false,
        message: String = ""
    ) {
        buffer.writeInteger(OracleMockServer.MessageID.error.rawValue)
        buffer.writeInteger(UInt8(0))  // end of call status
        buffer.writeInteger(UInt8(0))  // end to end seq#
        buffer.writeInteger(UInt8(0))  // current row number
        buffer.writeInteger(UInt8(0))  // error number
        buffer.writeInteger(UInt8(0))  // array elem error
        buffer.writeInteger(UInt8(0))  // array elem error
        buffer.writeUB2(cursorID)  // cursor id
        buffer.writeUB2(position)  // error position
        buffer.writeInteger(UInt8(0))  // sql type
        buffer.writeInteger(UInt8(0))  // fatal?
        buffer.writeInteger(UInt8(0))  // flags
        buffer.writeInteger(UInt8(0))  // user cursor options
        buffer.writeInteger(UInt8(0))  // UDI parameter
        buffer.writeInteger(UInt8(0))  // warning flag

        // row id
        buffer.writeInteger(UInt8(0))  // rba
        buffer.writeInteger(UInt8(0))  // partition id
        buffer.writeInteger(UInt8(0))  // ?
        buffer.writeInteger(UInt8(0))  // block number
        buffer.writeInteger(UInt8(0))  // slot number

        buffer.writeInteger(UInt8(0))  // OS error
        buffer.writeInteger(UInt8(0))  // statement number
        buffer.writeInteger(UInt8(0))  // call number
        buffer.writeInteger(UInt8(0))  // padding
        buffer.writeInteger(UInt8(0))  // success iters
        buffer.writeInteger(UInt8(0))  // oerrdd (logical rowid)
        buffer.writeInteger(UInt8(0))  // batch error codes array
        buffer.writeInteger(UInt8(0))  // batch error row offset array
        buffer.writeInteger(UInt8(0))  // batch error messages array

        buffer.writeUB4(number)
        buffer.writeUB8(rowCount)

        buffer.writeInteger(UInt8(0))  // sql type
        buffer.writeInteger(UInt8(0))  // server checksum

        if number != 0 {
            buffer.writeInteger(UInt8(message.count))
            buffer.writeString(message)
        }
    }

    // MARK: - Private Methods -

    private mutating func clearIfNeeded() {
        switch self.state {
        case .flushed:
            self.state = .writable
            self.buffer.clear()
        case .writable:
            break
        }
    }

    /// Starts a new request with a placeholder for the header, which is set at the end of the request via
    /// ``endRequest``, and the data flags if they are required.
    mutating func startRequest(packetType: OracleMockServer.PacketType) {
        self.buffer.reserveCapacity(Self.headerSize)
        self.buffer.moveWriterIndex(forwardBy: Self.headerSize)
        if case let .data(flags, _) = packetType {
            self.buffer.writeInteger(flags)
        }
    }

    private mutating func endRequest(packetType: OracleMockServer.PacketType) {
        self.buffer.prepareSend(packetTypeByte: packetType.byte)
    }

    private mutating func writeFunctionCode(
        messageType: OracleMockServer.MessageID,
        functionCode: OracleMockServer.FunctionCode
    ) {
        self.sequenceNumber &+= 1
        if self.sequenceNumber == 0 {
            self.sequenceNumber = 1
        }
        self.buffer.writeInteger(messageType.rawValue)
        self.buffer.writeInteger(functionCode.rawValue)
        self.buffer.writeInteger(self.sequenceNumber)
        buffer.writeUB8(0)  // token number
    }

    private func encodeOracleNumberWithLength(_ value: Int, into buffer: inout ByteBuffer, ) {
        // The length of the parameter value, in bytes (this count does not
        // include itself). Can be zero.
        let lengthIndex = buffer.writerIndex
        buffer.writeInteger(0, as: UInt8.self)
        let startIndex = buffer.writerIndex
        // The value of the parameter, in the format indicated by the associated
        // format code.
        self.encodeOracleNumber(String(value).ascii, into: &buffer)

        // overwrite the empty length, with the real value.
        buffer.setInteger(
            numericCast(buffer.writerIndex - startIndex),
            at: lengthIndex, as: UInt8.self
        )
    }

    @discardableResult
    private func encodeOracleNumber(_ value: [UInt8], into buffer: inout ByteBuffer) -> Int {
        var writtenBytes = 0

        var numberOfDigits = 0
        var digits = [UInt8](repeating: 0, count: numberAsSingleChars)
        var isNegative = false
        var exponentIsNegative = false
        var position = 0
        var exponentPosition = 0
        var exponent: Int16 = 0
        var prependZero = false
        var appendSentinel = false

        let length = value.count

        // check to see if number is negative (first character is '-')
        if value.first == "-".ascii.first {
            isNegative = true
            position += 1
        }

        // scan for digits until the decimal point or exponent indicator found
        while position < length {
            if value[position] == ".".ascii.first || value[position] == "e".ascii.first
                || value[position] == "E".ascii.first
            {
                break
            }
            if value[position] < "0".ascii.first! || value[position] > "9".ascii.first! {
                preconditionFailure("\(value) can't logically be a numeric")
            }
            let digit = value[position] - "0".ascii.first!
            position += 1
            if digit == 0 && numberOfDigits == 0 {
                continue
            }
            digits[numberOfDigits] = digit
            numberOfDigits += 1
        }
        var decimalPointIndex = numberOfDigits

        // scan for digits following the decimal point, if applicable
        if position < length && value[position] == ".".ascii.first {
            position += 1
            while position < length {
                if value[position] == "e".ascii.first || value[position] == "E".ascii.first {
                    break
                }
                let digit = value[position] - "0".ascii.first!
                position += 1
                if digit == 0 && numberOfDigits == 0 {
                    decimalPointIndex -= 1
                    continue
                }
                digits[numberOfDigits] = digit
                numberOfDigits += 1
            }
        }

        // handle exponent, if applicable
        if position < length
            && (value[position] == "e".ascii.first || value[position] == "E".ascii.first)
        {
            position += 1
            if position < length {
                if value[position] == "-".ascii.first {
                    exponentIsNegative = true
                    position += 1
                } else if value[position] == "+".ascii.first {
                    position += 1
                }
            }
            exponentPosition = position
            while position < length {
                if value[position] < "0".ascii.first! || value[position] > "9".ascii.first! {
                    preconditionFailure("\(value) can't logically be a numeric")
                }
                position += 1
            }
            if exponentPosition == position {
                preconditionFailure("\(value) can't logically be a numeric")
            }
            exponent = Int16(
                value.dropFirst(exponentPosition).dropLast(position)
            )
            if exponentIsNegative {
                exponent = -exponent
            }
            decimalPointIndex += Int(exponent)
        }

        // if there is anything left in the string, that indicates an
        // invalid number as well
        if position < length {
            preconditionFailure("\(value) can't logically be a numeric")
        }

        // skip trailing zeros
        while numberOfDigits > 0 && digits[numberOfDigits - 1] == 0 {
            numberOfDigits -= 1
        }

        // value must be less than 1e126 and greater than 1e-129;
        // the number of digits also cannot exceed the maximum precision of
        // Oracle numbers
        if numberOfDigits > numberMaxDigits || decimalPointIndex > 126 || decimalPointIndex < -129 {
            preconditionFailure("\(value) can't logically be a numeric")
        }

        // if the exponent is odd, prepend a zero
        if decimalPointIndex % 2 == 1 {
            prependZero = true
            if numberOfDigits > 0 {
                digits[numberOfDigits] = 0
                numberOfDigits += 1
                decimalPointIndex += 1
            }
        }

        // determine the number of digit pairs; if the number of digits is odd,
        // append a zero to make the number of digits even
        if numberOfDigits % 2 == 1 {
            digits[numberOfDigits] = 0
            numberOfDigits += 1
        }
        let numberOfPairs = numberOfDigits / 2

        // append a sentinel 102 byte for negative numbers if there is room
        if isNegative && numberOfDigits > 0 && numberOfDigits < numberMaxDigits {
            appendSentinel = true
        }

        // if the number of digits is zero, the value is itself zero since all
        // leading and trailing zeros are removed from the digits string; this
        // is a special case
        if numberOfDigits == 0 {
            writtenBytes += buffer.writeInteger(UInt8(128))
            return writtenBytes
        }

        // write the exponent
        var exponentOnWire: UInt8 = UInt8((decimalPointIndex / 2) + 192)
        if isNegative {
            exponentOnWire = ~exponentOnWire
        }
        writtenBytes += buffer.writeInteger(exponentOnWire)

        // write the mantissa bytes
        var digitsPosition = 0
        for pair in 0..<numberOfPairs {
            var digit: UInt8
            if pair == 0 && prependZero {
                digit = digits[digitsPosition]
                digitsPosition += 1
            } else {
                digit = digits[digitsPosition] * 10 + digits[digitsPosition + 1]
                digitsPosition += 2
            }
            if isNegative {
                digit = 101 - digit
            } else {
                digit += 1
            }
            writtenBytes += buffer.writeInteger(digit)
        }

        // append 102 bytes for negative numbers if the number of digits is less
        // than the maximum allowable
        if appendSentinel {
            writtenBytes += buffer.writeInteger(UInt8(102))
        }

        return writtenBytes
    }
}

extension ByteBuffer {
    fileprivate mutating func prepareSend(
        packetTypeByte: UInt8,
        packetFlags: UInt8 = 0
    ) {
        self.writeInteger(UInt8(29))  // eof
        var position = 0
        self.setInteger(UInt32(self.readableBytes), at: position)
        position += MemoryLayout<UInt32>.size
        self.setInteger(packetTypeByte, at: position)
        position += MemoryLayout<UInt8>.size
        self.setInteger(packetFlags, at: position)
        position += MemoryLayout<UInt8>.size
        self.setInteger(UInt16(0), at: position)
        position += MemoryLayout<UInt16>.size
    }
}

extension StringProtocol {
    fileprivate var ascii: [UInt8] { compactMap(\.asciiValue) }
}

extension SignedInteger {
    fileprivate init(_ bytes: [UInt8]) {
        precondition(bytes.count <= MemoryLayout<Self>.size)

        var value: Int64 = 0

        for byte in bytes {
            value <<= 8
            value |= Int64(byte)
        }

        self.init(value)
    }
}
