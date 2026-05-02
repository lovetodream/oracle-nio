//===----------------------------------------------------------------------===//
//
// This source file is part of the OracleNIO open source project
//
// Copyright (c) 2026 Timo Zacherl and the OracleNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
// See CONTRIBUTORS.md for the list of OracleNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIOCore

public struct IntervalYM: Sendable, Equatable, Hashable {
    public var years: Int
    public var months: Int

    @inlinable
    public init(years: Int, months: Int) {
        self.years = years
        self.months = months
    }
}

extension IntervalYM: ExpressibleByIntegerLiteral {
    @inlinable
    public init(integerLiteral value: Int) {
        self.init(years: value / 12, months: value % 12)
    }

    @inlinable
    public var totalMonths: Int {
        years * 12 + months
    }
}

extension IntervalYM: Encodable {
    @inlinable
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(totalMonths)
    }
}

extension IntervalYM: Decodable {
    @inlinable
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let total = try container.decode(Int.self)
        self = .init(years: total / 12, months: total % 12)
    }
}

extension IntervalYM: OracleEncodable {
    @inlinable
    public static var defaultOracleType: OracleDataType { .intervalYM }

    @inlinable
    public func encode(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext
    ) {
        let biasedYears = UInt32(bitPattern: Int32(years)) &+ 0x8000_0000
        buffer.writeInteger(biasedYears, endianness: .big)
        buffer.writeInteger(UInt8(months + 60))
    }
}

extension IntervalYM: OracleDecodable {
    @inlinable
    public init(
        from buffer: inout ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext
    ) throws {
        switch type {
        case .intervalYM:
            guard buffer.readableBytes >= 5 else {
                throw OracleDecodingError.Code.missingData
            }
            let biasedYears = try buffer.throwingReadInteger(endianness: .big, as: UInt32.self)
            let monthsByte = try buffer.throwingReadInteger(as: UInt8.self)
            let years = Int(Int32(bitPattern: biasedYears &- 0x8000_0000))
            let months = Int(monthsByte) - 60
            self = .init(years: years, months: months)
        default:
            throw OracleDecodingError.Code.typeMismatch
        }
    }
}
