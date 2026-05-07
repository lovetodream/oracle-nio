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
import Testing

@testable import OracleNIO

#if canImport(FoundationEssentials)
    import FoundationEssentials
#else
    import Foundation
#endif

@Suite(.timeLimit(.minutes(5))) struct DateTests {
    private func makeTimestampBuffer(tzHourByte: UInt8?, tzMinuteByte: UInt8?) -> ByteBuffer {
        var buffer = ByteBuffer()
        buffer.writeInteger(UInt8(120))  // year hi: 100 + 2025/100
        buffer.writeInteger(UInt8(125))  // year lo: 100 + 2025%100
        buffer.writeInteger(UInt8(4))  // month
        buffer.writeInteger(UInt8(26))  // day
        buffer.writeInteger(UInt8(13))  // hour + 1 (12:00:00 UTC)
        buffer.writeInteger(UInt8(1))  // minute + 1 (0)
        buffer.writeInteger(UInt8(1))  // second + 1 (0)
        buffer.writeInteger(UInt32(0), endianness: .big, as: UInt32.self)  // fractional ns
        if let hb = tzHourByte, let mb = tzMinuteByte {
            buffer.writeInteger(hb)
            buffer.writeInteger(mb)
        }
        return buffer
    }

    private var expectedApril26Noon2025UTC: Date {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        return utc.date(
            from: DateComponents(
                calendar: utc, timeZone: TimeZone(secondsFromGMT: 0),
                year: 2025, month: 4, day: 26, hour: 12, minute: 0, second: 0, nanosecond: 0
            ))!
    }

    @Test(arguments: [
        // (offset description, tzHour, tzMinute)
        ("-07:00 (PST/MST)", -7, 0),
        ("-05:00 (EST)", -5, 0),
        ("-12:00 (Baker Island)", -12, 0),
        ("-03:30 (Newfoundland std)", -3, -30),
    ])
    func decodeTimestampTZWithNegativeOffset(
        _ label: String, tzHour: Int, tzMinute: Int
    ) throws {
        let hourByte = UInt8(tzHour + Int(Constants.TZ_HOUR_OFFSET))
        let minuteByte = UInt8(tzMinute + Int(Constants.TZ_MINUTE_OFFSET))
        var buffer = makeTimestampBuffer(tzHourByte: hourByte, tzMinuteByte: minuteByte)

        let decoded = try Date(from: &buffer, type: .timestampTZ, context: .default)
        #expect(decoded == expectedApril26Noon2025UTC, "offset \(label)")
    }

    @Test(arguments: [
        ("+00:00 (UTC)", 0, 0),
        ("+05:30 (IST)", 5, 30),
        ("+09:00 (JST)", 9, 0),
        ("+14:00 (Kiribati)", 14, 0),
    ])
    func decodeTimestampTZWithPositiveOffset(
        _ label: String, tzHour: Int, tzMinute: Int
    ) throws {
        let hourByte = UInt8(tzHour + Int(Constants.TZ_HOUR_OFFSET))
        let minuteByte = UInt8(tzMinute + Int(Constants.TZ_MINUTE_OFFSET))
        var buffer = makeTimestampBuffer(tzHourByte: hourByte, tzMinuteByte: minuteByte)

        let decoded = try Date(from: &buffer, type: .timestampTZ, context: .default)
        #expect(decoded == expectedApril26Noon2025UTC, "offset \(label)")
    }

    @Test func decodeTimestampLTZWithNegativeOffset() throws {
        let hourByte = UInt8(-7 + Int(Constants.TZ_HOUR_OFFSET))
        let minuteByte = UInt8(0 + Int(Constants.TZ_MINUTE_OFFSET))
        var buffer = makeTimestampBuffer(tzHourByte: hourByte, tzMinuteByte: minuteByte)
        let decoded = try Date(from: &buffer, type: .timestampLTZ, context: .default)
        #expect(decoded == expectedApril26Noon2025UTC)
    }

    @Test func decodeTimestampWithoutTimeZone() throws {
        var buffer = makeTimestampBuffer(tzHourByte: nil, tzMinuteByte: nil)
        let decoded = try Date(from: &buffer, type: .timestamp, context: .default)
        #expect(decoded == expectedApril26Noon2025UTC)
    }

}
