// Copyright 2024 Timo Zacherl
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OracleNIO
import NIOCore

final class OracleCodableTests: XCTestCase {

    func testDecodeAnOptionalFromARow() {
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
                    nullsAllowed: true
                ), count: 2
            )
        )

        var result: (String?, String?)
        XCTAssertNoThrow(result = try row.decode(
            (String?, String?).self, context: .default)
        )
        XCTAssertNil(result.0)
        XCTAssertEqual(result.1, "Hello world!")
    }

    func testDecodeOracleNumbersFromARow() {
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
                    nullsAllowed: true
                ),
                .init(
                    name: "float",
                    dataType: .number,
                    dataTypeSize: 1,
                    precision: 1,
                    scale: 1,
                    bufferSize: 1,
                    nullsAllowed: true
                ),
                .init(
                    name: "double",
                    dataType: .number,
                    dataTypeSize: 1,
                    precision: 1,
                    scale: 1,
                    bufferSize: 1,
                    nullsAllowed: true
                ),
            ]
        )

        var result: (OracleNumber?, OracleNumber?, OracleNumber?)
        XCTAssertNoThrow(result = try row.decode(
            (OracleNumber?, OracleNumber?, OracleNumber?).self,
            context: .default)
        )
        XCTAssert(result.0?.double == 42)
        XCTAssert(result.1?.double == -24.42)
        XCTAssert(result.2?.double == 420.08150042)
    }

    func testDecodeDateFromARow() {
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
                    nullsAllowed: true
                )
            ]
        )

        var result: (Date?)
        XCTAssertNoThrow(result = try row.decode(
            (Date?).self, context: .default
        ))
        XCTAssert(
            Calendar.current.isDate(
                date, equalTo: result ?? .distantPast, toGranularity: .second
            )
        )
    }

    func testDecodeDifferentNumericsFromARow() {
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
                    nullsAllowed: true
                ),
                .init(
                    name: "float",
                    dataType: .binaryFloat,
                    dataTypeSize: 1,
                    precision: 1,
                    scale: 1,
                    bufferSize: 1,
                    nullsAllowed: true
                ),
                .init(
                    name: "double",
                    dataType: .binaryDouble,
                    dataTypeSize: 1,
                    precision: 1,
                    scale: 1,
                    bufferSize: 1,
                    nullsAllowed: true
                ),
            ]
        )

        var result: (Int?, Float?, Double?)
        XCTAssertNoThrow(result = try row.decode(
            (Int?, Float?, Double?).self, context: .default)
        )
        XCTAssertEqual(result.0, 42)
        XCTAssertEqual(result.1, 24.42)
        XCTAssertEqual(result.2, 420.081500420)
    }

}

extension DataRow: ExpressibleByArrayLiteral {
    public typealias ArrayLiteralElement = OracleThrowingEncodable

    public init(arrayLiteral elements: any OracleThrowingEncodable...) {
        var buffer = ByteBuffer()
        let encodingContext = OracleEncodingContext(jsonEncoder: JSONEncoder())
        elements.forEach { element in
            try! element._encodeRaw(into: &buffer, context: encodingContext)
        }
        self.init(columnCount: elements.count, bytes: buffer)
    }

    static func makeTestDataRow(_ encodables: (any OracleEncodable)?...) -> DataRow {
        var bytes = ByteBuffer()
        encodables.forEach { column in
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
