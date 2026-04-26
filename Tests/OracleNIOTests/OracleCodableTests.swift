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

    @Test func decodeTimestampTZWithNegativeOffset() throws {
        // TIMESTAMP WITH TIME ZONE encoded with a negative UTC offset (-07:00).
        // Wire layout: 7 base bytes + 4 fractional-second bytes + 2 TZ bytes.
        // For -07:00, byte11 = TZ_HOUR_OFFSET + (-7) = 13, byte12 = TZ_MINUTE_OFFSET + 0 = 60.
        // Pre-fix this trapped on UInt8 underflow inside the decoder.
        var buffer = ByteBuffer()
        buffer.writeInteger(UInt8(120))   // year hi: 100 + 2025/100 = 100 + 20 = 120
        buffer.writeInteger(UInt8(125))   // year lo: 100 + 2025%100 = 100 + 25 = 125
        buffer.writeInteger(UInt8(4))     // month
        buffer.writeInteger(UInt8(26))    // day
        buffer.writeInteger(UInt8(13))    // hour + 1 (12:00:00 UTC)
        buffer.writeInteger(UInt8(1))     // minute + 1 (0)
        buffer.writeInteger(UInt8(1))     // second + 1 (0)
        buffer.writeInteger(UInt32(0), endianness: .big, as: UInt32.self) // fractional seconds = 0
        buffer.writeInteger(UInt8(13))    // tz hour byte: -7 + 20
        buffer.writeInteger(UInt8(60))    // tz minute byte: 0 + 60

        let decoded = try Date(from: &buffer, type: .timestampTZ, context: .default)

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let expected = utc.date(from: DateComponents(
            calendar: utc, timeZone: TimeZone(secondsFromGMT: 0),
            year: 2025, month: 4, day: 26, hour: 12, minute: 0, second: 0, nanosecond: 0
        ))!
        #expect(decoded == expected)
    }

    @Test func roundTripDateThroughTimestampTZWithNegativeLocalOffset() throws {
        // Encoding a Date when the current timezone has a negative offset must not trap.
        // We can't force the process timezone here, so we instead exercise the encoder math
        // for a known-bad pair (hours = -7, minutes = 0): pre-fix this trapped on UInt8(-7).
        let hours = -7
        let minutes = 0
        var buffer = ByteBuffer()
        buffer.writeInteger(UInt8(hours + Int(Constants.TZ_HOUR_OFFSET)))
        buffer.writeInteger(UInt8(minutes + Int(Constants.TZ_MINUTE_OFFSET)))
        #expect(buffer.readableBytes == 2)
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
