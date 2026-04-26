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
import Testing

@testable import OracleNIO

#if canImport(FoundationEssentials)
    import FoundationEssentials
#else
    import Foundation
#endif


@Suite(.timeLimit(.minutes(5))) struct OracleCodableTests {

    @Test func decodeAnOptionalFromARow() throws {
        let row = OracleRow(
            lookupTable: ["id": 0, "name": 1],
            data: .makeTestDataRow(nil, "Hello world!"),
            columns: .init(
                repeating: .init(
                    name: "id",
                    dataType: .varchar,
                    dataTypeSize: 1,
                    precision: 1,
                    scale: 1,
                    bufferSize: 1,
                    nullsAllowed: true,
                    typeScheme: nil,
                    typeName: nil,
                    domainSchema: nil,
                    domainName: nil,
                    annotations: [:],
                    vectorDimensions: nil,
                    vectorFormat: nil
                ), count: 2
            )
        )

        let result = try row.decode((String?, String?).self, context: .default)
        #expect(result.0 == nil)
        #expect(result.1 == "Hello world!")
    }

    @Test func decodeOracleNumbersFromARow() throws {
        let row = OracleRow(
            lookupTable: ["int": 0, "float": 1, "double": 2],
            data: .makeTestDataRow(
                OracleNumber(42),
                OracleNumber(-24.42),
                OracleNumber(420.08150042)
            ),
            columns: [
                .init(
                    name: "int",
                    dataType: .number,
                    dataTypeSize: 1,
                    precision: 1,
                    scale: 1,
                    bufferSize: 1,
                    nullsAllowed: true,
                    typeScheme: nil,
                    typeName: nil,
                    domainSchema: nil,
                    domainName: nil,
                    annotations: [:],
                    vectorDimensions: nil,
                    vectorFormat: nil
                ),
                .init(
                    name: "float",
                    dataType: .number,
                    dataTypeSize: 1,
                    precision: 1,
                    scale: 1,
                    bufferSize: 1,
                    nullsAllowed: true,
                    typeScheme: nil,
                    typeName: nil,
                    domainSchema: nil,
                    domainName: nil,
                    annotations: [:],
                    vectorDimensions: nil,
                    vectorFormat: nil
                ),
                .init(
                    name: "double",
                    dataType: .number,
                    dataTypeSize: 1,
                    precision: 1,
                    scale: 1,
                    bufferSize: 1,
                    nullsAllowed: true,
                    typeScheme: nil,
                    typeName: nil,
                    domainSchema: nil,
                    domainName: nil,
                    annotations: [:],
                    vectorDimensions: nil,
                    vectorFormat: nil
                ),
            ]
        )

        let result = try row.decode((OracleNumber?, OracleNumber?, OracleNumber?).self, context: .default)
        #expect(result.0?.doubleValue == 42)
        #expect(result.1?.doubleValue == -24.42)
        #expect(result.2?.doubleValue == 420.08150042)
    }

    @Test func decodeDateFromARow() throws {
        let date = Date()
        let row = OracleRow(
            lookupTable: ["date": 0],
            data: .makeTestDataRow(date),
            columns: [
                .init(
                    name: "date",
                    dataType: .timestampTZ,
                    dataTypeSize: 1,
                    precision: 1,
                    scale: 1,
                    bufferSize: 1,
                    nullsAllowed: true,
                    typeScheme: nil,
                    typeName: nil,
                    domainSchema: nil,
                    domainName: nil,
                    annotations: [:],
                    vectorDimensions: nil,
                    vectorFormat: nil
                )
            ]
        )

        let result = try row.decode(
            (Date?).self, context: .default
        )
        #expect(
            Calendar.current.isDate(
                date, equalTo: result ?? .distantPast, toGranularity: .second
            )
        )
    }

    /// Builds an Oracle TIMESTAMP-family wire buffer for 2025-04-26 12:00:00 UTC with the
    /// given timezone offset bytes appended (when non-nil). Year/month/day/hour/min/sec are
    /// always stored in UTC on the wire; the trailing two bytes only carry display zone.
    private func makeTimestampBuffer(tzHourByte: UInt8?, tzMinuteByte: UInt8?) -> ByteBuffer {
        var buffer = ByteBuffer()
        buffer.writeInteger(UInt8(120))  // year hi: 100 + 2025/100
        buffer.writeInteger(UInt8(125))  // year lo: 100 + 2025%100
        buffer.writeInteger(UInt8(4))    // month
        buffer.writeInteger(UInt8(26))   // day
        buffer.writeInteger(UInt8(13))   // hour + 1 (12:00:00 UTC)
        buffer.writeInteger(UInt8(1))    // minute + 1 (0)
        buffer.writeInteger(UInt8(1))    // second + 1 (0)
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
        return utc.date(from: DateComponents(
            calendar: utc, timeZone: TimeZone(secondsFromGMT: 0),
            year: 2025, month: 4, day: 26, hour: 12, minute: 0, second: 0, nanosecond: 0
        ))!
    }

    /// Regression: pre-fix, decoding a TIMESTAMP TZ with a negative UTC offset trapped on
    /// `UInt8(byte11) - UInt8(20)` underflow inside `Date.init(from:type:context:)`.
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

    /// Sanity: positive offsets continue to decode correctly after the Int-promotion fix.
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

        // For +00:00 both TZ bytes equal their offsets and the decoder skips the TZ branch
        // (`byte11 != 0 && byte12 != 0` guard). The result must still be the UTC instant.
        let decoded = try Date(from: &buffer, type: .timestampTZ, context: .default)
        #expect(decoded == expectedApril26Noon2025UTC, "offset \(label)")
    }

    /// TIMESTAMP WITH LOCAL TIME ZONE travels the same code path; cover it explicitly so
    /// the negative-offset fix is exercised for both wire types.
    @Test func decodeTimestampLTZWithNegativeOffset() throws {
        let hourByte = UInt8(-7 + Int(Constants.TZ_HOUR_OFFSET))
        let minuteByte = UInt8(0 + Int(Constants.TZ_MINUTE_OFFSET))
        var buffer = makeTimestampBuffer(tzHourByte: hourByte, tzMinuteByte: minuteByte)
        let decoded = try Date(from: &buffer, type: .timestampLTZ, context: .default)
        #expect(decoded == expectedApril26Noon2025UTC)
    }

    /// Plain TIMESTAMP (no TZ) — 11-byte buffer, no trailing offset bytes. Ensures the fix
    /// did not break the path that skips the TZ branch entirely.
    @Test func decodeTimestampWithoutTimeZone() throws {
        var buffer = makeTimestampBuffer(tzHourByte: nil, tzMinuteByte: nil)
        let decoded = try Date(from: &buffer, type: .timestamp, context: .default)
        #expect(decoded == expectedApril26Noon2025UTC)
    }

    @Test func decodeDifferentNumericsFromARow() throws {
        let row = OracleRow(
            lookupTable: ["int": 0, "float": 1, "double": 2],
            data: .makeTestDataRow(Int(42), Float(24.42), Double(420.081500420)),
            columns: [
                .init(
                    name: "int",
                    dataType: .binaryInteger,
                    dataTypeSize: 1,
                    precision: 1,
                    scale: 1,
                    bufferSize: 1,
                    nullsAllowed: true,
                    typeScheme: nil,
                    typeName: nil,
                    domainSchema: nil,
                    domainName: nil,
                    annotations: [:],
                    vectorDimensions: nil,
                    vectorFormat: nil
                ),
                .init(
                    name: "float",
                    dataType: .binaryFloat,
                    dataTypeSize: 1,
                    precision: 1,
                    scale: 1,
                    bufferSize: 1,
                    nullsAllowed: true,
                    typeScheme: nil,
                    typeName: nil,
                    domainSchema: nil,
                    domainName: nil,
                    annotations: [:],
                    vectorDimensions: nil,
                    vectorFormat: nil
                ),
                .init(
                    name: "double",
                    dataType: .binaryDouble,
                    dataTypeSize: 1,
                    precision: 1,
                    scale: 1,
                    bufferSize: 1,
                    nullsAllowed: true,
                    typeScheme: nil,
                    typeName: nil,
                    domainSchema: nil,
                    domainName: nil,
                    annotations: [:],
                    vectorDimensions: nil,
                    vectorFormat: nil
                ),
            ]
        )

        let result = try row.decode((Int?, Float?, Double?).self, context: .default)
        #expect(result.0 == 42)
        #expect(result.1 == 24.42)
        #expect(result.2 == 420.081500420)
    }

    @Test func decodeMalformedRowFailsWithDetails() {
        let row = OracleRow(
            lookupTable: ["int": 0],
            data: .init(columnCount: 1, bytes: .init(bytes: [1, 0])),
            columns: [
                .init(
                    name: "int",
                    dataType: .binaryInteger,
                    dataTypeSize: 1,
                    precision: 1,
                    scale: 1,
                    bufferSize: 1,
                    nullsAllowed: true,
                    typeScheme: nil,
                    typeName: nil,
                    domainSchema: nil,
                    domainName: nil,
                    annotations: [:],
                    vectorDimensions: nil,
                    vectorFormat: nil
                )
            ]
        )

        #expect(
            performing: {
                _ = try row.decode(String.self)
            },
            throws: { error in
                "\(error)".contains("columnName: ***")  // should be redacted
                    && String(reflecting: error).contains(#"columnName: "int""#)
            })
    }

}

extension DataRow: ExpressibleByArrayLiteral {
    public typealias ArrayLiteralElement = OracleThrowingEncodable

    public init(arrayLiteral elements: any OracleThrowingEncodable...) {
        var buffer = ByteBuffer()
        let encodingContext = OracleEncodingContext()
        for element in elements {
            try! element._encodeRaw(into: &buffer, context: encodingContext)
        }
        self.init(columnCount: elements.count, bytes: buffer)
    }

    static func makeTestDataRow(_ encodables: (any OracleEncodable)?...) -> DataRow {
        var bytes = ByteBuffer()
        for column in encodables {
            switch column {
            case .none:
                bytes.writeInteger(UInt8(0))
            case .some(let input):
                input._encodeRaw(into: &bytes, context: .default)
            }
        }

        return DataRow(columnCount: encodables.count, bytes: bytes)
    }
}
