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

    @Suite struct OracleJSONWriterTests {
        @Test func encodeNull() throws {
            var buffer = ByteBuffer()
            var writer = OracleJSONWriter()
            try writer.encode(.none, into: &buffer, maxFieldNameSize: 255)
            let result = try OracleJSONParser.parse(from: &buffer)
            #expect(result == .none)
        }

        @Test func encodeTrue() throws {
            var buffer = ByteBuffer()
            var writer = OracleJSONWriter()
            try writer.encode(.bool(true), into: &buffer, maxFieldNameSize: 255)
            let result = try OracleJSONParser.parse(from: &buffer)
            #expect(result == .bool(true))
        }

        @Test func encodeFalse() throws {
            var buffer = ByteBuffer()
            var writer = OracleJSONWriter()
            try writer.encode(.bool(false), into: &buffer, maxFieldNameSize: 255)
            let result = try OracleJSONParser.parse(from: &buffer)
            #expect(result == .bool(false))
        }

        @Test func encodeInt() throws {
            var buffer = ByteBuffer()
            var writer = OracleJSONWriter()
            try writer.encode(.int(1), into: &buffer, maxFieldNameSize: 255)
            let result = try OracleJSONParser.parse(from: &buffer)
            #expect(result == .double(1.0))
        }

        @Test func encodeFloat() throws {
            var buffer = ByteBuffer()
            var writer = OracleJSONWriter()
            try writer.encode(.float(1.0), into: &buffer, maxFieldNameSize: 255)
            let result = try OracleJSONParser.parse(from: &buffer)
            #expect(result == .double(1.0))
        }

        @Test func encodeDouble() throws {
            var buffer = ByteBuffer()
            var writer = OracleJSONWriter()
            try writer.encode(.double(1.0), into: &buffer, maxFieldNameSize: 255)
            let result = try OracleJSONParser.parse(from: &buffer)
            #expect(result == .double(1.0))
        }

        @Test func encodeDate() throws {
            var buffer = ByteBuffer()
            var writer = OracleJSONWriter()
            try writer.encode(
                .date(.init(timeIntervalSince1970: 500)), into: &buffer, maxFieldNameSize: 255)
            let result = try OracleJSONParser.parse(from: &buffer)
            #expect(result == .date(.init(timeIntervalSince1970: 500)))
        }

        @Test func encodeIntervalDS() throws {
            var buffer = ByteBuffer()
            var writer = OracleJSONWriter()
            try writer.encode(.intervalDS(15.0), into: &buffer, maxFieldNameSize: 255)
            let result = try OracleJSONParser.parse(from: &buffer)
            #expect(result == .intervalDS(15.0))
        }

        @Test func encodeShortString() throws {
            // expected
            // 0000 : FF 4A 5A 01 00 10 00 06 |.JZ.....|
            // 0008 : 05 76 61 6C 75 65       |.value  |
            var buffer = ByteBuffer()
            var writer = OracleJSONWriter()
            try writer.encode(.string("value"), into: &buffer, maxFieldNameSize: 255)
            let result = try OracleJSONParser.parse(from: &buffer)
            #expect(result == .string("value"))
        }

        @Test func encodeMediumString() throws {
            var buffer = ByteBuffer()
            var writer = OracleJSONWriter()
            let string = String(repeating: "a", count: 260)
            try writer.encode(.string(string), into: &buffer, maxFieldNameSize: 255)
            let result = try OracleJSONParser.parse(from: &buffer)
            #expect(result == .string(string))
        }

        @Test func encodeLongString() throws {
            var buffer = ByteBuffer()
            var writer = OracleJSONWriter()
            let string = String(repeating: "a", count: 65555)
            try writer.encode(.string(string), into: &buffer, maxFieldNameSize: 255)
            let result = try OracleJSONParser.parse(from: &buffer)
            #expect(result == .string(string))
        }

        @Test func encodeVectorBinary() throws {
            var buffer = ByteBuffer()
            var writer = OracleJSONWriter()
            try writer.encode(.vectorBinary([1, 2, 3]), into: &buffer, maxFieldNameSize: 255)
            let result = try OracleJSONParser.parse(from: &buffer)
            #expect(result == .vectorBinary([1, 2, 3]))
        }

        @Test func encodeVectorInt8() throws {
            var buffer = ByteBuffer()
            var writer = OracleJSONWriter()
            try writer.encode(.vectorInt8([1, 2, 3]), into: &buffer, maxFieldNameSize: 255)
            let result = try OracleJSONParser.parse(from: &buffer)
            #expect(result == .vectorInt8([1, 2, 3]))
        }

        @Test func encodeVectorFloat32() throws {
            var buffer = ByteBuffer()
            var writer = OracleJSONWriter()
            try writer.encode(
                .vectorFloat32([1.1, 2.2, 3.3]), into: &buffer, maxFieldNameSize: 255)
            let result = try OracleJSONParser.parse(from: &buffer)
            #expect(result == .vectorFloat32([1.1, 2.2, 3.3]))
        }

        @Test func encodeVectorFloat64() throws {
            var buffer = ByteBuffer()
            var writer = OracleJSONWriter()
            try writer.encode(
                .vectorFloat64([1.1, 2.2, 3.3]), into: &buffer, maxFieldNameSize: 255)
            let result = try OracleJSONParser.parse(from: &buffer)
            #expect(result == .vectorFloat64([1.1, 2.2, 3.3]))
        }

        @Test func encodeStringArray() throws {
            var buffer = ByteBuffer()
            var writer = OracleJSONWriter()
            try writer.encode(
                .array([.string("hello"), .string("there")]),
                into: &buffer,
                maxFieldNameSize: 255
            )
            let result = try OracleJSONParser.parse(from: &buffer)
            #expect(result == .array([.string("hello"), .string("there")]))
        }

        @Test func encodeObject() throws {
            var buffer = ByteBuffer()
            var writer = OracleJSONWriter()
            try writer.encode(
                .container(["hello": .string("there")]),
                into: &buffer,
                maxFieldNameSize: 255
            )
            let result = try OracleJSONParser.parse(from: &buffer)
            #expect(result == .container(["hello": .string("there")]))
        }

        @Test func encodeObjectWithMultipleKeys() throws {
            var buffer = ByteBuffer()
            var writer = OracleJSONWriter()
            try writer.encode(
                .container([
                    "hello": .string("there"),
                    "foo": .string("bar"),
                ]),
                into: &buffer,
                maxFieldNameSize: 255
            )
            let result = try OracleJSONParser.parse(from: &buffer)
            #expect(
                result
                    == .container([
                        "hello": .string("there"),
                        "foo": .string("bar"),
                    ]))
        }

        @Test func encodeObjectLongValue() throws {
            var buffer = ByteBuffer()
            var writer = OracleJSONWriter()
            let string = String(repeating: "a", count: 66666)
            try writer.encode(
                .array([.string(string)]),
                into: &buffer,
                maxFieldNameSize: 255
            )
            let result = try OracleJSONParser.parse(from: &buffer)
            #expect(result == .array([.string(string)]))
        }

        @Test func encodeObjectWithManyKeys() throws {
            var buffer = ByteBuffer()
            var writer = OracleJSONWriter()
            var dict = [String: OracleJSONStorage]()
            for i in 0..<260 {
                dict["\(i)"] = .string("\(i)")
            }
            try writer.encode(.container(dict), into: &buffer, maxFieldNameSize: 255)
            let result = try OracleJSONParser.parse(from: &buffer)
            #expect(result == .container(dict))
        }

        @Test func encodeObjectWithLongFieldName() throws {
            var buffer = ByteBuffer()
            var writer = OracleJSONWriter()
            let key = String(repeating: "a", count: 500)
            try writer.encode(
                .container([key: .string("value")]), into: &buffer, maxFieldNameSize: 65535)
            let result = try OracleJSONParser.parse(from: &buffer)
            #expect(result == .container([key: .string("value")]))
        }

        @Test func encodeObjectWithNestedObjectArray() throws {
            var buffer = ByteBuffer()
            var writer = OracleJSONWriter()
            let json: OracleJSONStorage = .container([
                "name": .string("String"),
                "address": .container([
                    "city": .string("String"),
                    "street": .string("String"),
                    "zip": .string("String"),
                ]),
                "email": .array([.string("String")]),
                "phone": .array([.string("String")]),
                "web": .array([.string("String")]),
                "openingHours": .array([
                    .container([
                        "day_of_week": .string("Tuesday"),
                        "opens": .string("08:00"),
                        "closes": .string("18:00"),
                    ])
                ]),
            ])

            try writer.encode(json, into: &buffer, maxFieldNameSize: 65535)
            let result = try OracleJSONParser.parse(from: &buffer)
            #expect(result == json)
        }
    }
#endif
