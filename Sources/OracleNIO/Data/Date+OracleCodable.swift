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

import struct Foundation.Calendar
import struct Foundation.Date
import struct Foundation.DateComponents
import struct Foundation.TimeZone
import func Foundation.pow

extension Date: OracleEncodable {
    public var oracleType: OracleDataType { .timestampTZ }

    public func encode<JSONEncoder: OracleJSONEncoder>(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext<JSONEncoder>
    ) {
        var length = self.oracleType.bufferSizeFactor
        let currentCalendarTimeZone = Calendar.current
            .dateComponents([.timeZone], from: self).timeZone!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second, .nanosecond],
            from: self
        )
        let year = components.year!
        buffer.writeInteger(UInt8(year / 100 + 100))
        buffer.writeInteger(UInt8(year % 100 + 100))
        buffer.writeInteger(UInt8(components.month!))
        buffer.writeInteger(UInt8(components.day!))
        buffer.writeInteger(UInt8(components.hour! + 1))
        buffer.writeInteger(UInt8(components.minute! + 1))
        buffer.writeInteger(UInt8(components.second! + 1))
        if length > 7 {
            let fractionalSeconds =
                UInt32(components.nanosecond! / 1_000_000)
            if fractionalSeconds == 0 && length <= 11 {
                length = 7
            } else {
                buffer.writeInteger(
                    fractionalSeconds, endianness: .big, as: UInt32.self
                )
            }
        }
        if length > 11 {
            let seconds = currentCalendarTimeZone.secondsFromGMT()
            let totalMinutes = seconds / 60
            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60
            buffer.writeInteger(UInt8(hours) + Constants.TZ_HOUR_OFFSET)
            buffer.writeInteger(UInt8(minutes) + Constants.TZ_MINUTE_OFFSET)
        }
    }
}

extension Date: OracleDecodable {
    public init<JSONDecoder: OracleJSONDecoder>(
        from buffer: inout ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext<JSONDecoder>
    ) throws {
        switch type {
        case .date, .timestamp, .timestampLTZ, .timestampTZ:
            let length = buffer.readableBytes
            guard
                length >= 7,
                let firstSevenBytes = buffer.readBytes(length: 7)
            else {
                throw OracleDecodingError.Code.missingData
            }

            let year = (Int(firstSevenBytes[0]) - 100) * 100 + Int(firstSevenBytes[1]) - 100
            let month = Int(firstSevenBytes[2])
            let day = Int(firstSevenBytes[3])
            let hour = Int(firstSevenBytes[4]) - 1
            let minute = Int(firstSevenBytes[5]) - 1
            let second = Int(firstSevenBytes[6]) - 1
            var nanosecond = 0

            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!

            if length >= 11,
                let value = buffer.readInteger(
                    endianness: .big, as: UInt32.self
                )
            {
                let fsecond = Double(value) / pow(10, Double(String(value).count))
                nanosecond = Int(fsecond * 1_000_000_000)
            }

            let (byte11, byte12) =
                buffer
                .readMultipleIntegers(as: (UInt8, UInt8).self) ?? (0, 0)

            if length > 11 && byte11 != 0 && byte12 != 0 {
                if byte11 & Constants.TNS_HAS_REGION_ID != 0 {
                    // Named time zones are not supported
                    throw OracleDecodingError.Code.failure
                }

                let tzHour = Int(byte11 - Constants.TZ_HOUR_OFFSET)
                let tzMinute = Int(byte12 - Constants.TZ_MINUTE_OFFSET)
                if tzHour != 0 || tzMinute != 0 {
                    guard
                        let timeZone = TimeZone(
                            secondsFromGMT: tzHour * 3600 + tzMinute * 60
                        )
                    else {
                        throw OracleDecodingError.Code.failure
                    }
                    calendar.timeZone = timeZone
                }
            }

            let components = DateComponents(
                calendar: calendar,
                timeZone: TimeZone(secondsFromGMT: 0)!,  // dates are always UTC
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute,
                second: second,
                nanosecond: nanosecond
            )

            guard let value = calendar.date(from: components) else {
                throw OracleDecodingError.Code.failure
            }
            self = value
        default:
            throw OracleDecodingError.Code.typeMismatch
        }
    }
}
