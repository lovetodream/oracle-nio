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

#if compiler(>=6.0)
    import NIOCore
    import Testing

    @testable import OracleNIO

    import struct Foundation.Date

    @Suite struct OracleJSONParserTests {
        let header = [
            Constants.TNS_JSON_MAGIC_BYTE_1,
            Constants.TNS_JSON_MAGIC_BYTE_2,
            Constants.TNS_JSON_MAGIC_BYTE_3,
            Constants.TNS_JSON_VERSION_MAX_FNAME_255,
        ]

        @Test func wrongHeader() {
            var buffer = ByteBuffer(bytes: [
                Constants.TNS_JSON_MAGIC_BYTE_1,
                Constants.TNS_JSON_MAGIC_BYTE_2,
                Constants.TNS_JSON_MAGIC_BYTE_2,
            ])
            #expect(
                performing: {
                    try OracleJSONParser.parse(from: &buffer)
                },
                throws: { error in
                    error as? OracleError.ErrorType == .unexpectedData
                })
        }

        @Test func invalidVersion() {
            var buffer = ByteBuffer(bytes: [
                Constants.TNS_JSON_MAGIC_BYTE_1,
                Constants.TNS_JSON_MAGIC_BYTE_2,
                Constants.TNS_JSON_MAGIC_BYTE_3,
                0,
            ])
            #expect(
                performing: {
                    try OracleJSONParser.parse(from: &buffer)
                },
                throws: { error in
                    error as? OracleError.ErrorType == .osonVersionNotSupported
                })
        }

        @Test func scalarTreeSegment16() throws {
            var buffer = ByteBuffer(bytes: header)
            buffer.writeInteger(Constants.TNS_JSON_FLAG_IS_SCALAR, as: UInt16.self)
            buffer.writeInteger(0x06, as: UInt16.self)  // tree segment size
            try buffer.writeLengthPrefixed(as: UInt8.self) {
                $0.writeString("value")
            }
            let value = try OracleJSONParser.parse(from: &buffer)
            #expect(value == .string("value"))
        }

        @Test func scalarTreeSegment32() throws {
            var buffer = ByteBuffer(bytes: header)
            buffer.writeInteger(
                Constants.TNS_JSON_FLAG_IS_SCALAR | Constants.TNS_JSON_FLAG_TREE_SEG_UINT32,
                as: UInt16.self)
            buffer.writeInteger(0x06, as: UInt32.self)  // tree segment size
            try buffer.writeLengthPrefixed(as: UInt8.self) {
                $0.writeString("value")
            }
            let value = try OracleJSONParser.parse(from: &buffer)
            #expect(value == .string("value"))
        }

        @Test func array() throws {
            // 0000 : FF 4A 5A 01 20 07 00 00 |.JZ.....|
            // 0008 : 00 00 0A 00 01 C0 01 00 |........|
            // 0016 : 04 05 76 61 6C 75 65    |..value |
            var buffer = ByteBuffer(bytes: header)
            buffer.writeInteger(0x2007, as: UInt16.self)  // flags
            buffer.writeInteger(0x00, as: UInt8.self)  // field names count
            buffer.writeInteger(0x0000, as: UInt16.self)  // field names segment size
            buffer.writeInteger(0x0A00, as: UInt16.self)  // tree segment size
            buffer.writeInteger(0x0001, as: UInt16.self)  // tiny nodes count
            buffer.writeInteger(Constants.TNS_JSON_TYPE_ARRAY)
            buffer.writeInteger(0x01, as: UInt8.self)  // array length
            buffer.writeInteger(0x0004, as: UInt16.self)  // offset
            try buffer.writeLengthPrefixed(as: UInt8.self) {
                $0.writeString("value")
            }
            let value = try OracleJSONParser.parse(from: &buffer)
            #expect(value == .array([.string("value")]))
        }

        @Test func singleKeyObject() async throws {
            // 0000 : FF 4A 5A 01 21 07 01 00 |.JZ.!...|
            // 0008 : 04 00 09 00 00 D7 00 00 |........|
            // 0016 : 03 66 6F 6F 84 01 01 00 |.foo....|
            // 0024 : 05 03 62 61 72          |..bar   |
            var buffer = ByteBuffer(bytes: header)
            buffer.writeInteger(0x2107, as: UInt16.self)  // flags
            buffer.writeInteger(0x01, as: UInt8.self)  // field names count
            buffer.writeInteger(0x0004, as: UInt16.self)  // field names segment size
            buffer.writeInteger(0x0009, as: UInt16.self)  // tree segment size
            buffer.writeInteger(0x0000, as: UInt16.self)  // tiny nodes count
            buffer.writeBytes([0xD7])  // hash ids
            buffer.writeBytes([0x00, 0x00])  // field name offsets
            // field names
            try buffer.writeLengthPrefixed(as: UInt8.self) {
                $0.writeString("foo")
            }
            buffer.writeInteger(Constants.TNS_JSON_TYPE_OBJECT)
            buffer.writeInteger(0x01, as: UInt8.self)  // object keys count
            buffer.writeInteger(0x01, as: UInt8.self)  // one based index
            buffer.writeInteger(0x0005, as: UInt16.self)  // value offset
            try buffer.writeLengthPrefixed(as: UInt8.self) {
                $0.writeString("bar")
            }
            let value = try OracleJSONParser.parse(from: &buffer)
            #expect(value == .container(["foo": .string("bar")]))
        }

        @Test func emptyString() throws {
            var buffer = ByteBuffer(bytes: header)
            buffer.writeInteger(
                Constants.TNS_JSON_FLAG_IS_SCALAR | Constants.TNS_JSON_FLAG_TREE_SEG_UINT32,
                as: UInt16.self)
            buffer.writeInteger(0x06, as: UInt32.self)  // tree segment size
            try buffer.writeLengthPrefixed(as: UInt8.self) {
                $0.writeString("")
            }
            let value = try OracleJSONParser.parse(from: &buffer)
            #expect(value == .string(""))
        }

        @Test func sharedKeyObjects() throws {
            // 0000 : FF 4A 5A 01 21 07 01 00 |.JZ.!...|
            // 0008 : 04 00 1A 00 01 D7 00 00 |........|
            // 0016 : 03 66 6F 6F C0 02 00 06 |.foo....|
            // 0024 : 00 10 86 01 01 00 05 04 |........|
            // 0032 : 62 61 72 31 9C 00 06 00 |bar1....|
            // 0040 : 05 04 62 61 72 32       |..bar2  |
            var buffer = ByteBuffer(bytes: header)
            buffer.writeInteger(0x2107, as: UInt16.self)  // flags
            buffer.writeInteger(0x01, as: UInt8.self)  // field names count
            buffer.writeInteger(0x0004, as: UInt16.self)  // field names segment size
            buffer.writeInteger(0x001A, as: UInt16.self)  // tree segment size
            buffer.writeInteger(0x0001, as: UInt16.self)  // tiny nodes count
            buffer.writeBytes([0xD7])  // hash ids
            buffer.writeBytes([0x00, 0x00])  // field name offsets
            // field names
            try buffer.writeLengthPrefixed(as: UInt8.self) {
                $0.writeString("foo")
            }
            buffer.writeInteger(Constants.TNS_JSON_TYPE_ARRAY)
            buffer.writeInteger(0x02, as: UInt8.self)  // array length
            buffer.writeInteger(0x0006, as: UInt16.self)  // offset
            buffer.writeInteger(0x0010, as: UInt16.self)  // ?
            buffer.writeInteger(0x86, as: UInt8.self)  // key object id
            buffer.writeInteger(0x01, as: UInt8.self)  // object keys count
            buffer.writeInteger(0x01, as: UInt8.self)  // one based index
            buffer.writeInteger(0x0005, as: UInt16.self)  // offset
            try buffer.writeLengthPrefixed(as: UInt8.self) {
                $0.writeString("bar1")
            }
            buffer.writeInteger(0x9C, as: UInt8.self)  // shared key object id
            buffer.writeInteger(0x0006, as: UInt16.self)  // key offset
            buffer.writeInteger(0x0005, as: UInt16.self)  // value offset
            try buffer.writeLengthPrefixed(as: UInt8.self) {
                $0.writeString("bar2")
            }
            let value = try OracleJSONParser.parse(from: &buffer)
            #expect(
                value
                    == .array([
                        .container(["foo": .string("bar1")]),
                        .container(["foo": .string("bar2")]),
                    ]))
        }

        static let scalarValueArguments:
            [(@Sendable (inout ByteBuffer) throws -> Void, OracleJSONStorage)] =
                [
                    ({ buffer in buffer.writeInteger(Constants.TNS_JSON_TYPE_NULL) }, .none),
                    ({ buffer in buffer.writeInteger(Constants.TNS_JSON_TYPE_TRUE) }, .bool(true)),
                    (
                        { buffer in buffer.writeInteger(Constants.TNS_JSON_TYPE_FALSE) },
                        .bool(false)
                    ),
                    (
                        { buffer in
                            buffer.writeInteger(Constants.TNS_JSON_TYPE_DATE)
                            Date(timeIntervalSince1970: 500_000).encode(
                                into: &buffer, context: .default)
                        }, .date(.init(timeIntervalSince1970: 500_000))
                    ),
                    (
                        { buffer in
                            buffer.writeInteger(Constants.TNS_JSON_TYPE_TIMESTAMP)
                            Date(timeIntervalSince1970: 500_000).encode(
                                into: &buffer, context: .default)
                        }, .date(.init(timeIntervalSince1970: 500_000))
                    ),
                    (
                        { buffer in
                            buffer.writeInteger(Constants.TNS_JSON_TYPE_TIMESTAMP_TZ)
                            Date(timeIntervalSince1970: 500_000).encode(
                                into: &buffer, context: .default)
                        }, .date(.init(timeIntervalSince1970: 500_000))
                    ),
                    (
                        { buffer in
                            buffer.writeInteger(Constants.TNS_JSON_TYPE_BINARY_FLOAT)
                            Float(1.0).encode(into: &buffer, context: .default)
                        }, .float(1.0)
                    ),
                    (
                        { buffer in
                            buffer.writeInteger(Constants.TNS_JSON_TYPE_BINARY_DOUBLE)
                            Double(1.0).encode(into: &buffer, context: .default)
                        }, .double(1.0)
                    ),
                    (
                        { buffer in
                            buffer.writeInteger(Constants.TNS_JSON_TYPE_INTERVAL_DS)
                            IntervalDS(15.0).encode(into: &buffer, context: .default)
                        }, .intervalDS(IntervalDS(15.0))
                    ),
                    (
                        { buffer in
                            buffer.writeInteger(Constants.TNS_JSON_TYPE_STRING_LENGTH_UINT8)
                            try buffer.writeLengthPrefixed(as: UInt8.self) {
                                $0.writeString("Hello, there!")
                            }
                        }, .string("Hello, there!")
                    ),
                    (
                        { buffer in
                            buffer.writeInteger(Constants.TNS_JSON_TYPE_STRING_LENGTH_UINT16)
                            try buffer.writeLengthPrefixed(as: UInt16.self) {
                                $0.writeString("Hello, there!")
                            }
                        }, .string("Hello, there!")
                    ),
                    (
                        { buffer in
                            buffer.writeInteger(Constants.TNS_JSON_TYPE_STRING_LENGTH_UINT32)
                            try buffer.writeLengthPrefixed(as: UInt32.self) {
                                $0.writeString("Hello, there!")
                            }
                        }, .string("Hello, there!")
                    ),
                    (
                        { buffer in
                            buffer.writeInteger(Constants.TNS_JSON_TYPE_NUMBER_LENGTH_UINT8)
                            OracleNumber(1.0)._encodeRaw(into: &buffer, context: .default)
                        }, .double(1.0)
                    ),
                    (
                        { buffer in
                            buffer.writeInteger(Constants.TNS_JSON_TYPE_BINARY_LENGTH_UINT16)
                            buffer.writeInteger(1, as: UInt16.self)
                        }, .int(1)
                    ),
                    (
                        { buffer in
                            buffer.writeInteger(Constants.TNS_JSON_TYPE_BINARY_LENGTH_UINT32)
                            buffer.writeInteger(1, as: UInt32.self)
                        }, .int(1)
                    ),
                    (
                        { buffer in
                            buffer.writeInteger(Constants.TNS_JSON_TYPE_EXTENDED)
                            buffer.writeInteger(Constants.TNS_JSON_TYPE_VECTOR)
                            OracleVectorBinary([1, 2, 3]).encodeForJSON(into: &buffer)
                        }, .vectorBinary([1, 2, 3])
                    ),
                    (
                        { buffer in
                            buffer.writeInteger(Constants.TNS_JSON_TYPE_EXTENDED)
                            buffer.writeInteger(Constants.TNS_JSON_TYPE_VECTOR)
                            OracleVectorInt8([1, 2, 3]).encodeForJSON(into: &buffer)
                        }, .vectorInt8([1, 2, 3])
                    ),
                    (
                        { buffer in
                            buffer.writeInteger(Constants.TNS_JSON_TYPE_EXTENDED)
                            buffer.writeInteger(Constants.TNS_JSON_TYPE_VECTOR)
                            OracleVectorFloat32([1.1, 2.2, 3.3]).encodeForJSON(into: &buffer)
                        }, .vectorFloat32([1.1, 2.2, 3.3])
                    ),
                    (
                        { buffer in
                            buffer.writeInteger(Constants.TNS_JSON_TYPE_EXTENDED)
                            buffer.writeInteger(Constants.TNS_JSON_TYPE_VECTOR)
                            OracleVectorFloat64([1.1, 2.2, 3.3]).encodeForJSON(into: &buffer)
                        }, .vectorFloat64([1.1, 2.2, 3.3])
                    ),
                ]

        @Test(arguments: scalarValueArguments)
        func scalarValue(
            writer: @Sendable @escaping (inout ByteBuffer) throws -> Void,
            expected: OracleJSONStorage
        ) throws {
            var buffer = ByteBuffer(bytes: header)
            buffer.writeInteger(
                Constants.TNS_JSON_FLAG_IS_SCALAR | Constants.TNS_JSON_FLAG_TREE_SEG_UINT32,
                as: UInt16.self)
            buffer.writeInteger(0x06, as: UInt32.self)  // tree segment size
            try writer(&buffer)
            let value = try OracleJSONParser.parse(from: &buffer)
            #expect(value == expected)
        }
    }
#endif
