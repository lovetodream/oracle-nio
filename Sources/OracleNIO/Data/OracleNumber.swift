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
import class Foundation.NSDecimalNumber

/// A primitive type used to encode numeric values to Oracle's `NUMBER` datatype.
///
/// If you want to send `NUMBER` values to your database, you need to wrap your numerics
/// (Float, Double) in this type. Otherwise they will be sent as their corresponding Oracle datatype.
///
///
/// ## Numeric type conversions
///
/// | Swift type | Oracle type |
/// | --- | --- |
/// | `Int` | `NUMBER` |
/// | `Float` | `BINARY_FLOAT` |
/// | `Double` | `BINARY_DOUBLE` |
/// | `OracleNumber` | `NUMBER` |
///
/// > Note: It's possible to decode `OracleNumber` to any numeric Swift type.
public struct OracleNumber:
    CustomStringConvertible, CustomDebugStringConvertible,
    ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral,
    LosslessStringConvertible, Equatable, Hashable, Sendable
{
    internal let value: ByteBuffer
    public let doubleValue: Double

    public var description: String {
        self.doubleValue.description
    }

    public var debugDescription: String {
        String(describing: value)
    }

    public init?(_ description: String) {
        guard let value = Double(description) else {
            return nil
        }
        self.init(value, ascii: value.ascii)
    }

    public init<T: FixedWidthInteger>(_ value: T) {
        self.init(.init(value), ascii: value.ascii)
    }

    public init(_ value: Float) {
        self.init(.init(value), ascii: value.ascii)
    }

    public init(_ value: Double) {
        self.init(.init(value), ascii: value.ascii)
    }

    public init(integerLiteral value: Int) {
        self.init(.init(value), ascii: value.ascii)
    }

    public init(floatLiteral value: Double) {
        self.init(value, ascii: value.ascii)
    }

    public init(decimal: Decimal) {
        self.init((decimal as NSDecimalNumber).doubleValue, ascii: decimal.description.ascii)
    }

    internal init(_ numeric: Double, ascii: [UInt8]) {
        var buffer = ByteBuffer()
        OracleNumeric.encodeNumeric(ascii, into: &buffer)
        self.value = buffer
        self.doubleValue = numeric
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.doubleValue == rhs.doubleValue
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.doubleValue)
    }
}

extension OracleNumber: OracleDecodable {
    public init(
        from buffer: inout ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext
    ) throws {
        self.doubleValue = try OracleNumeric.parseFloat(from: &buffer)
        buffer.moveReaderIndex(to: 0)
        self.value = buffer
    }
}

extension OracleNumber: OracleEncodable {
    public static var defaultOracleType: OracleDataType { .number }

    public func encode(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext
    ) {
        buffer.writeImmutableBuffer(self.value)
    }
}
