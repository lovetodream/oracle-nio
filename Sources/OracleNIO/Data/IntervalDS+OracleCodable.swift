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

public struct IntervalDS: Sendable, Equatable, Hashable {
    public var days: Int
    public var hours: Int
    public var minutes: Int
    public var seconds: Int
    public var fractionalSeconds: Int

    public init(days: Int, hours: Int, minutes: Int, seconds: Int, fractionalSeconds: Int) {
        self.days = days
        self.hours = hours
        self.minutes = minutes
        self.seconds = seconds
        self.fractionalSeconds = fractionalSeconds
    }
}

extension IntervalDS: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        var remaining = value
        let days = (remaining / (24 * 60 * 60)).rounded(.down)
        remaining -= Double(days) * 24 * 60 * 60
        let hours = (remaining / (60 * 60)).rounded(.down)
        remaining -= Double(hours) * 60 * 60
        let minutes = (remaining / 60).rounded(.down)
        remaining -= Double(minutes) * 60
        let seconds = remaining.rounded(.down)
        let fractionalSeconds = ((remaining - seconds) * 1000).rounded(.down)
        self = .init(
            days: Int(days),
            hours: Int(hours),
            minutes: Int(minutes),
            seconds: Int(seconds),
            fractionalSeconds: Int(fractionalSeconds)
        )
    }

    public var double: Double {
        return (Double(days) * 24 * 60 * 60) + (Double(hours) * 60 * 60) + (Double(minutes) * 60)
            + Double(seconds) + (Double(fractionalSeconds) / 1000)
    }
}

extension IntervalDS: Encodable {
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        if encoder is _OracleJSONEncoder {
            try container.encode(self)
        } else {
            try container.encode(double)
        }
    }
}

extension IntervalDS: Decodable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(Double.self)
        self = .init(floatLiteral: value)
    }
}

extension IntervalDS: OracleEncodable {
    public static var defaultOracleType: OracleDataType { .intervalDS }

    public func encode(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext
    ) {
        buffer.writeInteger(
            UInt32(self.days) + Constants.TNS_DURATION_MID, endianness: .big
        )
        buffer.writeInteger(UInt8(self.hours) + Constants.TNS_DURATION_OFFSET)
        buffer.writeInteger(UInt8(self.minutes) + Constants.TNS_DURATION_OFFSET)
        buffer.writeInteger(UInt8(self.seconds) + Constants.TNS_DURATION_OFFSET)
        buffer.writeInteger(
            UInt32(self.fractionalSeconds) + Constants.TNS_DURATION_MID,
            endianness: .big
        )
        buffer.writeInteger(UInt8(buffer.readableBytes))
    }
}

extension IntervalDS: OracleDecodable {
    public init(
        from buffer: inout ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext
    ) throws {
        switch type {
        case .intervalDS:
            let durationMid = Constants.TNS_DURATION_MID
            let durationOffset = Constants.TNS_DURATION_OFFSET
            let days = (buffer.readInteger(endianness: .big, as: UInt32.self) ?? 0) - durationMid
            let fractionalSeconds =
                try buffer.throwingGetInteger(at: 7, endianness: .big, as: UInt32.self)
                - durationMid
            let hours = try buffer.throwingGetInteger(at: 4, as: UInt8.self) - durationOffset
            let minutes = try buffer.throwingGetInteger(at: 5, as: UInt8.self) - durationOffset
            let seconds = try buffer.throwingGetInteger(at: 6, as: UInt8.self) - durationOffset
            self = .init(
                days: Int(days),
                hours: Int(hours),
                minutes: Int(minutes),
                seconds: Int(seconds),
                fractionalSeconds: Int(fractionalSeconds)
            )
        default:
            throw OracleDecodingError.Code.typeMismatch
        }
    }
}
