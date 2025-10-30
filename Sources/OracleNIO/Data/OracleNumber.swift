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
    @usableFromInline
    internal let value: ByteBuffer
    public let doubleValue: Double

    @inlinable
    public var description: String {
        self.doubleValue.description
    }

    @inlinable
    public var debugDescription: String {
        String(describing: value)
    }

    @inlinable
    public init?(_ description: String) {
        guard let value = Double(description) else {
            return nil
        }
        self.init(value, ascii: value.ascii)
    }

    @inlinable
    public init<T: FixedWidthInteger>(_ value: T) {
        self.init(.init(value), ascii: value.ascii)
    }

    @inlinable
    public init(_ value: Float) {
        self.init(.init(value), ascii: value.ascii)
    }

    @inlinable
    public init(_ value: Double) {
        self.init(.init(value), ascii: value.ascii)
    }

    @inlinable
    public init(integerLiteral value: Int) {
        self.init(.init(value), ascii: value.ascii)
    }

    @inlinable
    public init(floatLiteral value: Double) {
        self.init(value, ascii: value.ascii)
    }

    #if false  // currently unsupported: https://github.com/swiftlang/swift-foundation/issues/1285
        @inlinable
        public init(decimal: Decimal) {
            self.init((decimal as NSDecimalNumber).doubleValue, ascii: decimal.description.ascii)
        }
    #endif

    @inlinable
    internal init(_ numeric: Double, ascii: [UInt8]) {
        var buffer = ByteBuffer()
        OracleNumeric.encodeNumeric(ascii, into: &buffer)
        self.value = buffer
        self.doubleValue = numeric
    }

    @inlinable
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.doubleValue == rhs.doubleValue
    }

    @inlinable
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.doubleValue)
    }
}

extension OracleNumber: OracleDecodable {
    @inlinable
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
    @inlinable
    public static var defaultOracleType: OracleDataType { .number }

    @inlinable
    public func encode(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext
    ) {
        buffer.writeImmutableBuffer(self.value)
    }
}
