// Copyright 2024 Timo Zacherl
// SPDX-License-Identifier: Apache-2.0

import NIOCore
import struct Foundation.Decimal

public struct OracleNumber: 
    CustomStringConvertible, CustomDebugStringConvertible,
    ExpressibleByStringLiteral, ExpressibleByIntegerLiteral,
    ExpressibleByFloatLiteral, Equatable, Hashable, Sendable
{
    internal var value: ByteBuffer

    public var double: Double? {
        var value = self.value.getSlice(
            at: 1, length: self.value.readableBytes - 1
        )! // skip length
        return try? OracleNumeric.parseFloat(from: &value)
    }

    public var description: String {
        if let double = self.double {
            return "\(double)"
        }
        return "<invalid_number>"
    }

    public var debugDescription: String {
        String(describing: value)
    }

    public init<T: Numeric>(_ value: T) where T: LosslessStringConvertible {
        self.init(ascii: value.ascii)
    }

    public init(stringLiteral value: String) {
        self.init(ascii: value.ascii)
    }

    public init(integerLiteral value: Int) {
        self.init(ascii: value.ascii)
    }

    public init(floatLiteral value: Double) {
        self.init(ascii: value.ascii)
    }

    public init(decimal: Decimal) {
        self.init(ascii: decimal.description.ascii)
    }


    internal init(value: ByteBuffer) {
        self.value = value
    }

    internal init(ascii: [UInt8]) {
        var buffer = ByteBuffer()
        OracleNumeric.encodeNumeric(ascii, into: &buffer)
        self.init(value: buffer)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.double == rhs.double
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.double)
    }
}

extension OracleNumber: OracleDecodable {
    public init<JSONDecoder: OracleJSONDecoder>(
        from buffer: inout ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext<JSONDecoder>
    ) throws {
        var bufferWithLength = ByteBuffer(bytes: [UInt8(buffer.readableBytes)])
        bufferWithLength.writeBuffer(&buffer)
        self.value = bufferWithLength
    }
}

extension OracleNumber: OracleEncodable {
    public var oracleType: OracleDataType { .number }
    
    public func encode<JSONEncoder: OracleJSONEncoder>(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext<JSONEncoder>
    ) {
        buffer.writeImmutableBuffer(self.value)
    }
}
