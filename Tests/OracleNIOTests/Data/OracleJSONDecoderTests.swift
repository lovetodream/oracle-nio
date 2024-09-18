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
    import Testing

    @testable import OracleNIO

    import struct Foundation.Date

    @Suite struct OracleJSONDecoderTests {
        @Test func emptyObject() throws {
            let value = try OracleJSONDecoder().decode([String: String].self, from: .container([:]))
            #expect(value.isEmpty)
        }

        @Test func emptyArray() throws {
            let value = try OracleJSONDecoder().decode([String].self, from: .array([]))
            #expect(value.isEmpty)
        }

        @Test func decodingObjectFromArrayFails() throws {
            #expect(
                throws: DecodingError.self,
                performing: {
                    try OracleJSONDecoder().decode(
                        [String: String].self, from: .array([.string("foo")]))
                })
        }

        @Test func decodingArrayFromObjectFails() throws {
            #expect(
                throws: DecodingError.self,
                performing: {
                    try OracleJSONDecoder().decode(
                        [String].self, from: .container(["foo": .string("bar")]))
                })
        }

        @Test func decodeNil() throws {
            try decodeScalar(expected: String?.none, given: .none)
        }

        @Test func decodeBool() throws {
            try decodeScalar(expected: true, given: .bool(true))
        }

        @Test func decodeString() throws {
            try decodeScalar(expected: "foo", given: .string("foo"))
        }

        @Test func decodeOptionalString() throws {
            try decodeScalar(expected: Optional("foo"), given: .string("foo"))
        }

        @Test func decodeDouble() throws {
            try decodeScalar(expected: 1.23, given: .double(1.23))
        }

        @Test func decodeFloat() throws {
            try decodeScalar(expected: Float(1.23), given: .float(1.23))
        }

        @Test func decodeInt() throws {
            try decodeScalar(expected: 123, given: .int(123))
        }

        @Test func decodeInt8() throws {
            try decodeScalar(expected: Int8(123), given: .int(123))
        }

        @Test func decodeInt16() throws {
            try decodeScalar(expected: Int16(123), given: .int(123))
        }

        @Test func decodeInt32() throws {
            try decodeScalar(expected: Int32(123), given: .int(123))
        }

        @Test func decodeInt64() throws {
            try decodeScalar(expected: Int64(123), given: .int(123))
        }

        @Test func decodeUInt() throws {
            try decodeScalar(expected: UInt(123), given: .int(123))
        }

        @Test func decodeUInt8() throws {
            try decodeScalar(expected: UInt8(123), given: .int(123))
        }

        @Test func decodeUInt16() throws {
            try decodeScalar(expected: UInt16(123), given: .int(123))
        }

        @Test func decodeUInt32() throws {
            try decodeScalar(expected: UInt32(123), given: .int(123))
        }

        @Test func decodeUInt64() throws {
            try decodeScalar(expected: UInt64(123), given: .int(123))
        }

        @Test func decodeDate() throws {
            try decodeScalar(
                expected: Date(timeIntervalSince1970: 50_000),
                given: .date(Date(timeIntervalSince1970: 50_000))
            )
        }

        @Test func decodeIntervalDS() throws {
            try decodeScalar(
                expected: IntervalDS(floatLiteral: 15.0),
                given: .intervalDS(15.0)
            )
        }

        @Test func decodeVectorInt8() throws {
            try decodeScalar(
                expected: OracleVectorInt8([1, 2, 3, 4, 5, 6, 7, 8]),
                given: .vectorInt8([1, 2, 3, 4, 5, 6, 7, 8])
            )
        }

        @Test func decodeVectorFloat32() throws {
            try decodeScalar(
                expected: OracleVectorFloat32([1.0, 2.0, 3.0, 4.0, 5.0]),
                given: .vectorFloat32([1.0, 2.0, 3.0, 4.0, 5.0])
            )
        }

        @Test func decodeVectorFloat64() throws {
            try decodeScalar(
                expected: OracleVectorFloat64([1.0, 2.0, 3.0, 4.0, 5.0]),
                given: .vectorFloat64([1.0, 2.0, 3.0, 4.0, 5.0])
            )
        }
    }


    // MARK: Utility

    extension OracleJSONDecoderTests {
        private func decodeScalar<T: Decodable & Equatable>(expected: T, given: OracleJSONStorage)
            throws
        {
            let value = try OracleJSONDecoder().decode(T.self, from: given)
            #expect(value == expected)
        }
    }
#endif
