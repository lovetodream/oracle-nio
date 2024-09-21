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

@Suite struct OracleJSONEncoderTests {
    @Test func emptyObject() throws {
        let value = try _OracleJSONEncoder().encode([String: String]())
        #expect(value == .container([:]))
    }

    @Test func emptyArray() throws {
        let value = try _OracleJSONEncoder().encode([String]())
        #expect(value == .array([]))
    }


    // MARK: Scalars

    @Test func encodeNil() throws {
        try encodeScalar(String?.none, expected: .none)
    }

    @Test func encodeBool() throws {
        try encodeScalar(true, expected: .bool(true))
    }

    @Test func decodeStringFromIntFails() throws {
        #expect(throws: DecodingError.self, performing: {
            try OracleJSONDecoder().decode(String.self, from: .int(1))
        })
    }

    @Test func encodeString() throws {
        try encodeScalar("foo", expected: .string("foo"))
    }

    @Test func encodeOptionalString() throws {
        try encodeScalar(Optional("foo"), expected: .string("foo"))
    }

    @Test func encodeDouble() throws {
        try encodeScalar(1.23, expected: .double(1.23))
    }

    @Test func encodeFloat() throws {
        try encodeScalar(Float(1.23), expected: .float(1.23))
    }

    @Test func encodeInt() throws {
        try encodeScalar(123, expected: .int(123))
    }

    @Test func encodeIntTooLargeValueFails() throws {
        let encoder = _OracleJSONEncoder()
        var container = encoder.singleValueContainer()
        #expect(
            throws: EncodingError.self,
            performing: {
                try container.encode(UInt64.max)
            })
    }

    @Test func encodeInt8() throws {
        try encodeScalar(Int8(123), expected: .int(123))
    }

    @Test func encodeInt16() throws {
        try encodeScalar(Int16(123), expected: .int(123))
    }

    @Test func encodeInt32() throws {
        try encodeScalar(Int32(123), expected: .int(123))
    }

    @Test func encodeInt64() throws {
        try encodeScalar(Int64(123), expected: .int(123))
    }

    @Test func encodeUInt() throws {
        try encodeScalar(UInt(123), expected: .int(123))
    }

    @Test func encodeUInt8() throws {
        try encodeScalar(UInt8(123), expected: .int(123))
    }

    @Test func encodeUInt16() throws {
        try encodeScalar(UInt16(123), expected: .int(123))
    }

    @Test func encodeUInt32() throws {
        try encodeScalar(UInt32(123), expected: .int(123))
    }

    @Test func encodeUInt64() throws {
        try encodeScalar(UInt64(123), expected: .int(123))
    }

    @Test func encodeDate() throws {
        try encodeScalar(
            Date(timeIntervalSince1970: 50_000),
            expected: .date(Date(timeIntervalSince1970: 50_000))
        )
    }

    @Test func encodeIntervalDS() throws {
        try encodeScalar(
            IntervalDS(floatLiteral: 15.0),
            expected: .intervalDS(15.0)
        )
    }

    @Test func encodeVectorInt8() throws {
        try encodeScalar(
            OracleVectorInt8([1, 2, 3, 4, 5, 6, 7, 8]),
            expected: .vectorInt8([1, 2, 3, 4, 5, 6, 7, 8])
        )
    }

    @Test func encodeVectorFloat32() throws {
        try encodeScalar(
            OracleVectorFloat32([1.0, 2.0, 3.0, 4.0, 5.0]),
            expected: .vectorFloat32([1.0, 2.0, 3.0, 4.0, 5.0])
        )
    }

    @Test func encodeVectorFloat64() throws {
        try encodeScalar(
            OracleVectorFloat64([1.0, 2.0, 3.0, 4.0, 5.0]),
            expected: .vectorFloat64([1.0, 2.0, 3.0, 4.0, 5.0])
        )
    }

    @Test func encodeDateInSingleValueContainer() throws {
        let encoder = _OracleJSONEncoder()
        var container = encoder.singleValueContainer()
        try container.encode(Date(timeIntervalSince1970: 50_000))
        #expect(encoder.value == .date(Date(timeIntervalSince1970: 50_000)))
    }

    @Test func encodeIntervalDSInSingleValueContainer() throws {
        let encoder = _OracleJSONEncoder()
        var container = encoder.singleValueContainer()
        try container.encode(IntervalDS(floatLiteral: 15.0))
        #expect(encoder.value == .intervalDS(15.0))
    }

    @Test func encodeVectorInt8InSingleValueContainer() throws {
        let encoder = _OracleJSONEncoder()
        var container = encoder.singleValueContainer()
        try container.encode(OracleVectorInt8([1, 2, 3]))
        #expect(encoder.value == .vectorInt8([1, 2, 3]))
    }

    @Test func encodeVectorFloat32InSingleValueContainer() throws {
        let encoder = _OracleJSONEncoder()
        var container = encoder.singleValueContainer()
        try container.encode(OracleVectorFloat32([1.1, 2.2, 3.3]))
        #expect(encoder.value == .vectorFloat32([1.1, 2.2, 3.3]))
    }

    @Test func encodeVectorFloat64InSingleValueContainer() throws {
        let encoder = _OracleJSONEncoder()
        var container = encoder.singleValueContainer()
        try container.encode(OracleVectorFloat64([1.1, 2.2, 3.3]))
        #expect(encoder.value == .vectorFloat64([1.1, 2.2, 3.3]))
    }


    // MARK: Keyed Decoding Container

    @Suite struct KeyedEncodingContainerTests {
        @Test func encodeNull() throws {
            let encoder = _OracleJSONEncoder()
            enum CodingKeys: CodingKey {
                case hello
            }

            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeNil(forKey: .hello)
            #expect(encoder.value == .container([:]))
        }

        @Test func encodeBool() throws {
            let encoder = _OracleJSONEncoder()
            enum CodingKeys: CodingKey {
                case hello
            }

            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(true, forKey: .hello)
            #expect(encoder.value == .container(["hello": .bool(true)]))
        }

        @Test func encodeString() throws {
            let encoder = _OracleJSONEncoder()
            enum CodingKeys: CodingKey {
                case hello
            }

            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("world", forKey: .hello)
            #expect(encoder.value == .container(["hello": .string("world")]))
        }

        @Test func encodeDouble() throws {
            let encoder = _OracleJSONEncoder()
            enum CodingKeys: CodingKey {
                case hello
            }

            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(Double(1.0), forKey: .hello)
            #expect(encoder.value == .container(["hello": .double(1.0)]))
        }

        @Test func encodeFloat() throws {
            let encoder = _OracleJSONEncoder()
            enum CodingKeys: CodingKey {
                case hello
            }

            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(Float(1.0), forKey: .hello)
            #expect(encoder.value == .container(["hello": .float(1.0)]))
        }

        @Test func encodeIntTooLargeValueFails() throws {
            let encoder = _OracleJSONEncoder()
            enum CodingKeys: CodingKey {
                case hello
            }

            var container = encoder.container(keyedBy: CodingKeys.self)
            #expect(
                throws: EncodingError.self,
                performing: {
                    try container.encode(UInt64.max, forKey: .hello)
                })
        }

        @Test func encodeInt() throws {
            let encoder = _OracleJSONEncoder()
            enum CodingKeys: CodingKey {
                case hello
            }

            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(1, forKey: .hello)
            #expect(encoder.value == .container(["hello": .int(1)]))
        }

        @Test func encodeInt8() throws {
            let encoder = _OracleJSONEncoder()
            enum CodingKeys: CodingKey {
                case hello
            }

            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(Int8(1), forKey: .hello)
            #expect(encoder.value == .container(["hello": .int(1)]))
        }

        @Test func encodeInt16() throws {
            let encoder = _OracleJSONEncoder()
            enum CodingKeys: CodingKey {
                case hello
            }

            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(Int16(1), forKey: .hello)
            #expect(encoder.value == .container(["hello": .int(1)]))
        }

        @Test func encodeInt32() throws {
            let encoder = _OracleJSONEncoder()
            enum CodingKeys: CodingKey {
                case hello
            }

            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(Int32(1), forKey: .hello)
            #expect(encoder.value == .container(["hello": .int(1)]))
        }

        @Test func encodeInt64() throws {
            let encoder = _OracleJSONEncoder()
            enum CodingKeys: CodingKey {
                case hello
            }

            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(Int64(1), forKey: .hello)
            #expect(encoder.value == .container(["hello": .int(1)]))
        }

        @Test func encodeUInt() throws {
            let encoder = _OracleJSONEncoder()
            enum CodingKeys: CodingKey {
                case hello
            }

            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(UInt(1), forKey: .hello)
            #expect(encoder.value == .container(["hello": .int(1)]))
        }

        @Test func encodeUInt8() throws {
            let encoder = _OracleJSONEncoder()
            enum CodingKeys: CodingKey {
                case hello
            }

            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(UInt8(1), forKey: .hello)
            #expect(encoder.value == .container(["hello": .int(1)]))
        }

        @Test func encodeUInt16() throws {
            let encoder = _OracleJSONEncoder()
            enum CodingKeys: CodingKey {
                case hello
            }

            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(UInt16(1), forKey: .hello)
            #expect(encoder.value == .container(["hello": .int(1)]))
        }

        @Test func encodeUInt32() throws {
            let encoder = _OracleJSONEncoder()
            enum CodingKeys: CodingKey {
                case hello
            }

            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(UInt32(1), forKey: .hello)
            #expect(encoder.value == .container(["hello": .int(1)]))
        }

        @Test func encodeUInt64() throws {
            let encoder = _OracleJSONEncoder()
            enum CodingKeys: CodingKey {
                case hello
            }

            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(UInt64(1), forKey: .hello)
            #expect(encoder.value == .container(["hello": .int(1)]))
        }

        @Test func encodeDate() throws {
            let encoder = _OracleJSONEncoder()
            enum CodingKeys: CodingKey {
                case hello
            }

            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(Date(timeIntervalSince1970: 500), forKey: .hello)
            #expect(encoder.value == .container([
                "hello": .date(.init(timeIntervalSince1970: 500))
            ]))
        }

        @Test func encodeIntervalDS() throws {
            let encoder = _OracleJSONEncoder()
            enum CodingKeys: CodingKey {
                case hello
            }

            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(IntervalDS(floatLiteral: 15.0), forKey: .hello)
            #expect(encoder.value == .container([
                "hello": .intervalDS(15.0)
            ]))
        }

        @Test func encodeVectorInt8() throws {
            let encoder = _OracleJSONEncoder()
            enum CodingKeys: CodingKey {
                case hello
            }

            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(OracleVectorInt8([1, 2, 3]), forKey: .hello)
            #expect(encoder.value == .container([
                "hello": .vectorInt8([1, 2, 3])
            ]))
        }

        @Test func encodeVectorFloat32() throws {
            let encoder = _OracleJSONEncoder()
            enum CodingKeys: CodingKey {
                case hello
            }

            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(OracleVectorFloat32([1.1, 2.2, 3.3]), forKey: .hello)
            #expect(encoder.value == .container([
                "hello": .vectorFloat32([1.1, 2.2, 3.3])
            ]))
        }

        @Test func encodeVectorFloat64() throws {
            let encoder = _OracleJSONEncoder()
            enum CodingKeys: CodingKey {
                case hello
            }

            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(OracleVectorFloat64([1.1, 2.2, 3.3]), forKey: .hello)
            #expect(encoder.value == .container([
                "hello": .vectorFloat64([1.1, 2.2, 3.3])
            ]))
        }

        @Test func encodeGeneric() throws {
            let encoder = _OracleJSONEncoder()
            enum CodingKeys: CodingKey {
                case hello
            }

            var container = encoder.container(keyedBy: CodingKeys.self)
            func encode<T: Encodable>(_ value: T) throws {
                try container.encode(value, forKey: .hello)
            }
            try encode("foo")
            #expect(encoder.value == .container(["hello": .string("foo")]))
        }

        @Test func encodeNestedKey() throws {
            let encoder = _OracleJSONEncoder()
            struct Object: Encodable, Equatable {
                struct Nested: Encodable, Equatable {
                    let hello: String
                    enum CodingKeys: CodingKey {
                        case hello
                    }
                }
                let nested: Nested
                enum CodingKeys: CodingKey {
                    case nested
                }
            }
            try Object(nested: .init(hello: "there")).encode(to: encoder)
            #expect(encoder.value == .container(["nested": .container(["hello": .string("there")])]))
        }

        @Test func getNestedContainer() throws {
            let encoder = _OracleJSONEncoder()
            enum CodingKeys: CodingKey {
                case nested
                enum Nested: CodingKey {
                    case hello
                }
            }
            var container = encoder.container(keyedBy: CodingKeys.self)
            var nested = container.nestedContainer(
                keyedBy: CodingKeys.Nested.self, forKey: .nested)
            try nested.encode("there", forKey: .hello)
            #expect(encoder.value == .container(["nested": .container(["hello": .string("there")])]))
        }

        @Test func getNestedUnkeyedContainer() throws {
            let encoder = _OracleJSONEncoder()
            enum CodingKeys: CodingKey {
                case nested
            }
            var container = encoder.container(keyedBy: CodingKeys.self)
            var nested = container.nestedUnkeyedContainer(forKey: .nested)
            try nested.encode("there")
            #expect(encoder.value == .container(["nested": .array([.string("there")])]))
        }

        @Test func getSuperEncoder() throws {
            let encoder = _OracleJSONEncoder()
            enum CodingKeys: CodingKey {
                case nested
            }
            var container = encoder.container(keyedBy: CodingKeys.self)
            #expect(container.superEncoder() as? _OracleJSONEncoder === encoder)
            #expect(container.superEncoder(forKey: .nested) as? _OracleJSONEncoder === encoder)
        }
    }


    // MARK: Keyed Decoding Container

    @Suite struct UnkeyedEncodingContainerTests {
        @Test func encodeNull() throws {
            let encoder = _OracleJSONEncoder()
            var container = encoder.unkeyedContainer()
            try container.encodeNil()
            #expect(encoder.value == .array([]))
            #expect(container.count == 0)
        }

        @Test func encodeBool() throws {
            let encoder = _OracleJSONEncoder()
            var container = encoder.unkeyedContainer()
            try container.encode(true)
            #expect(encoder.value == .array([.bool(true)]))
            #expect(container.count == 1)
        }

        @Test func encodeString() throws {
            let encoder = _OracleJSONEncoder()
            var container = encoder.unkeyedContainer()
            try container.encode("world")
            #expect(encoder.value == .array([.string("world")]))
            #expect(container.count == 1)
        }

        @Test func encodeDouble() throws {
            let encoder = _OracleJSONEncoder()
            var container = encoder.unkeyedContainer()
            try container.encode(Double(1.0))
            #expect(encoder.value == .array([.double(1.0)]))
            #expect(container.count == 1)
        }

        @Test func encodeFloat() throws {
            let encoder = _OracleJSONEncoder()
            var container = encoder.unkeyedContainer()
            try container.encode(Float(1.0))
            #expect(encoder.value == .array([.float(1.0)]))
            #expect(container.count == 1)
        }

        @Test func encodeIntTooLargeValueFails() throws {
            let encoder = _OracleJSONEncoder()
            var container = encoder.unkeyedContainer()
            #expect(
                throws: EncodingError.self,
                performing: {
                    try container.encode(UInt64.max)
                })
        }

        @Test func encodeInt() throws {
            let encoder = _OracleJSONEncoder()
            var container = encoder.unkeyedContainer()
            try container.encode(1)
            #expect(encoder.value == .array([.int(1)]))
            #expect(container.count == 1)
        }

        @Test func encodeInt8() throws {
            let encoder = _OracleJSONEncoder()
            var container = encoder.unkeyedContainer()
            try container.encode(Int8(1))
            #expect(encoder.value == .array([.int(1)]))
            #expect(container.count == 1)
        }

        @Test func encodeInt16() throws {
            let encoder = _OracleJSONEncoder()
            var container = encoder.unkeyedContainer()
            try container.encode(Int16(1))
            #expect(encoder.value == .array([.int(1)]))
            #expect(container.count == 1)
        }

        @Test func encodeInt32() throws {
            let encoder = _OracleJSONEncoder()
            var container = encoder.unkeyedContainer()
            try container.encode(Int32(1))
            #expect(encoder.value == .array([.int(1)]))
            #expect(container.count == 1)
        }

        @Test func encodeInt64() throws {
            let encoder = _OracleJSONEncoder()
            var container = encoder.unkeyedContainer()
            try container.encode(Int64(1))
            #expect(encoder.value == .array([.int(1)]))
            #expect(container.count == 1)
        }

        @Test func encodeUInt() throws {
            let encoder = _OracleJSONEncoder()
            var container = encoder.unkeyedContainer()
            try container.encode(UInt(1))
            #expect(encoder.value == .array([.int(1)]))
            #expect(container.count == 1)
        }

        @Test func encodeUInt8() throws {
            let encoder = _OracleJSONEncoder()
            var container = encoder.unkeyedContainer()
            try container.encode(UInt8(1))
            #expect(encoder.value == .array([.int(1)]))
            #expect(container.count == 1)
        }

        @Test func encodeUInt16() throws {
            let encoder = _OracleJSONEncoder()
            var container = encoder.unkeyedContainer()
            try container.encode(UInt16(1))
            #expect(encoder.value == .array([.int(1)]))
            #expect(container.count == 1)
        }

        @Test func encodeUInt32() throws {
            let encoder = _OracleJSONEncoder()
            var container = encoder.unkeyedContainer()
            try container.encode(UInt32(1))
            #expect(encoder.value == .array([.int(1)]))
            #expect(container.count == 1)
        }

        @Test func encodeUInt64() throws {
            let encoder = _OracleJSONEncoder()
            var container = encoder.unkeyedContainer()
            try container.encode(UInt64(1))
            #expect(encoder.value == .array([.int(1)]))
            #expect(container.count == 1)
        }

        @Test func encodeDate() throws {
            let encoder = _OracleJSONEncoder()
            var container = encoder.unkeyedContainer()
            try container.encode(Date(timeIntervalSince1970: 500))
            #expect(encoder.value == .array([.date(.init(timeIntervalSince1970: 500))]))
            #expect(container.count == 1)
        }

        @Test func encodeIntervalDS() throws {
            let encoder = _OracleJSONEncoder()
            var container = encoder.unkeyedContainer()
            try container.encode(IntervalDS(floatLiteral: 15.0))
            #expect(encoder.value == .array([.intervalDS(15.0)]))
            #expect(container.count == 1)
        }

        @Test func encodeVectorInt8() throws {
            let encoder = _OracleJSONEncoder()
            var container = encoder.unkeyedContainer()
            try container.encode(OracleVectorInt8([1, 2, 3]))
            #expect(encoder.value == .array([.vectorInt8([1, 2, 3])]))
            #expect(container.count == 1)
        }

        @Test func encodeVectorFloat32() throws {
            let encoder = _OracleJSONEncoder()
            var container = encoder.unkeyedContainer()
            try container.encode(OracleVectorFloat32([1.1, 2.2, 3.3]))
            #expect(encoder.value == .array([.vectorFloat32([1.1, 2.2, 3.3])]))
            #expect(container.count == 1)
        }

        @Test func encodeVectorFloat64() throws {
            let encoder = _OracleJSONEncoder()
            var container = encoder.unkeyedContainer()
            try container.encode(OracleVectorFloat64([1.1, 2.2, 3.3]))
            #expect(encoder.value == .array([.vectorFloat64([1.1, 2.2, 3.3])]))
            #expect(container.count == 1)
        }

        @Test func encodeGeneric() throws {
            let encoder = _OracleJSONEncoder()
            var container = encoder.unkeyedContainer()
            func encode<T: Encodable>(_ value: T) throws {
                try container.encode(value)
            }
            try encode("foo")
            #expect(encoder.value == .array([.string("foo")]))
            #expect(container.count == 1)
        }

        @Test func encodeNestedContainer() throws {
            let encoder = _OracleJSONEncoder()
            enum CodingKeys: CodingKey {
                case hello
            }
            var container = encoder.unkeyedContainer()
            var nestedContainer = container.nestedContainer(keyedBy: CodingKeys.self)
            try nestedContainer.encode("there", forKey: .hello)
            #expect(encoder.value == .array([.container(["hello": .string("there")])]))
            #expect(container.count == 1)
        }

        @Test func encodeNestedUnkeyedContainer() throws {
            let encoder = _OracleJSONEncoder()
            var container = encoder.unkeyedContainer()
            var nested = container.nestedUnkeyedContainer()
            try nested.encode("there")
            #expect(encoder.value == .array([.array([.string("there")])]))
            #expect(container.count == 1)
            #expect(nested.count == 1)
        }
    }
}


// MARK: Utility

extension OracleJSONEncoderTests {
    private func encodeScalar<T: Encodable & Equatable>(_ value: T, expected: OracleJSONStorage)
    throws
    {
        let value = try _OracleJSONEncoder().encode(value)
        #expect(value == expected)
    }
}
#endif
