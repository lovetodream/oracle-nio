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

public import NIOCore

extension Double: OracleEncodable {
    @inlinable
    public static var defaultOracleType: OracleDataType {
        .binaryDouble
    }

    @inlinable
    public func encode(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext
    ) {
        let allBits = self.bitPattern
        let transformed: UInt64
        if allBits & 0x8000_0000_0000_0000 == 0 {
            // positive: flip the sign bit
            transformed = allBits | 0x8000_0000_0000_0000
        } else {
            // negative: invert all bits
            transformed = ~allBits
        }
        buffer.writeInteger(transformed, endianness: .big)
    }
}

extension Double: OracleDecodable {
    @inlinable
    public init(
        from buffer: inout ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext
    ) throws {
        switch type {
        case .number, .binaryInteger:
            self = try OracleNumeric.parseFloat(from: &buffer)
        case .binaryFloat:
            self = Double(try OracleNumeric.parseBinaryFloat(from: &buffer))
        case .binaryDouble:
            self = try OracleNumeric.parseBinaryDouble(from: &buffer)
        case .intervalDS:
            self = try IntervalDS(
                from: &buffer, type: type, context: context
            ).double
        default:
            throw OracleDecodingError.Code.typeMismatch
        }
    }
}
