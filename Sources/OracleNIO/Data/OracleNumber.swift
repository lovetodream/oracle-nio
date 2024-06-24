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

import struct Foundation.Decimal

/// A primitive type used to encode numeric values to Oracle's `NUMBER` datatype.
///
/// If you want to send `NUMBER` values to your database, you need to wrap your numerics
/// (Int, Float, Double) in this type. Otherwise they will be sent as their corresponding Oracle datatype.
///
///
/// ## Numeric type conversions
///
/// | Swift type | Oracle type |
/// | --- | --- |
/// | `Int` | `BINARY_INTEGER` |
/// | `Float` | `BINARY_FLOAT` |
/// | `Double` | `BINARY_DOUBLE` |
/// | `OracleNumber` | `NUMBER` |
///
/// > Note: It's possible to decode `OracleNumber` to any numeric Swift type.
public struct OracleNumber:
    CustomStringConvertible, CustomDebugStringConvertible,
    ExpressibleByStringLiteral, ExpressibleByIntegerLiteral,
    ExpressibleByFloatLiteral, Equatable, Hashable, Sendable
{
    internal var value: ByteBuffer

    public var double: Double? {
        var value = self.value.getSlice(
            at: 1, length: self.value.readableBytes - 1
        )!  // skip length
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
