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


        // MARK: Scalars

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


        // MARK: Keyed Decoding Container

        @Suite struct KeyedDecodingContainerTests {
            @Test func allKeys() throws {
                let decoder = _OracleJSONDecoder(
                    codingPath: [],
                    userInfo: [:],
                    value: .container(["hello": .none, "world": .none])
                )
                enum CodingKeys: CodingKey {
                    case hello
                }

                let container = try decoder.container(keyedBy: CodingKeys.self)
                let keys = container.allKeys
                #expect(keys.count == 1)
                #expect(keys.first == .hello)
            }

            @Test func contains() throws {
                let decoder = _OracleJSONDecoder(
                    codingPath: [],
                    userInfo: [:],
                    value: .container(["hello": .none, "world": .none])
                )
                enum CodingKeys: CodingKey {
                    case hello
                    case bye
                }

                let container = try decoder.container(keyedBy: CodingKeys.self)
                #expect(container.contains(.hello))
                #expect(!container.contains(.bye))
            }

            @Test func decodeNullFromNothing() throws {
                let decoder = _OracleJSONDecoder(
                    codingPath: [],
                    userInfo: [:],
                    value: .container([:])
                )
                enum CodingKeys: CodingKey {
                    case hello
                }

                let container = try decoder.container(keyedBy: CodingKeys.self)
                #expect(
                    throws: DecodingError.self,
                    performing: {
                        try container.decodeNil(forKey: .hello)
                    })
            }

            @Test func decodeNull() throws {
                let decoder = _OracleJSONDecoder(
                    codingPath: [],
                    userInfo: [:],
                    value: .container(["hello": .none])
                )
                enum CodingKeys: CodingKey {
                    case hello
                }

                let container = try decoder.container(keyedBy: CodingKeys.self)
                #expect(try container.decodeNil(forKey: .hello))
            }

            @Test func decodeNullFromArray() throws {
                let decoder = _OracleJSONDecoder(
                    codingPath: [],
                    userInfo: [:],
                    value: .container(["hello": .array([])])
                )
                enum CodingKeys: CodingKey {
                    case hello
                }

                let container = try decoder.container(keyedBy: CodingKeys.self)
                #expect(try container.decodeNil(forKey: .hello) == false)
            }

            @Test func decodeBoolFromNumber() throws {
                let decoder = _OracleJSONDecoder(
                    codingPath: [],
                    userInfo: [:],
                    value: .container(["hello": .int(1)])
                )
                enum CodingKeys: CodingKey {
                    case hello
                }

                let container = try decoder.container(keyedBy: CodingKeys.self)
                #expect(
                    throws: DecodingError.self,
                    performing: {
                        try container.decode(Bool.self, forKey: .hello)
                    })
            }

            @Test func decodeBool() throws {
                let decoder = _OracleJSONDecoder(
                    codingPath: [],
                    userInfo: [:],
                    value: .container(["hello": .bool(true)])
                )
                enum CodingKeys: CodingKey {
                    case hello
                }

                let container = try decoder.container(keyedBy: CodingKeys.self)
                #expect(try container.decode(Bool.self, forKey: .hello))
            }

            @Test func decodeStringFromNumber() throws {
                let decoder = _OracleJSONDecoder(
                    codingPath: [],
                    userInfo: [:],
                    value: .container(["hello": .int(1)])
                )
                enum CodingKeys: CodingKey {
                    case hello
                }

                let container = try decoder.container(keyedBy: CodingKeys.self)
                #expect(
                    throws: DecodingError.self,
                    performing: {
                        try container.decode(String.self, forKey: .hello)
                    })
            }

            @Test func decodeString() throws {
                let decoder = _OracleJSONDecoder(
                    codingPath: [],
                    userInfo: [:],
                    value: .container(["hello": .string("world")])
                )
                enum CodingKeys: CodingKey {
                    case hello
                }

                let container = try decoder.container(keyedBy: CodingKeys.self)
                #expect(try container.decode(String.self, forKey: .hello) == "world")
            }

            @Test func decodeDoubleFromString() throws {
                let decoder = _OracleJSONDecoder(
                    codingPath: [],
                    userInfo: [:],
                    value: .container(["hello": .string("1")])
                )
                enum CodingKeys: CodingKey {
                    case hello
                }

                let container = try decoder.container(keyedBy: CodingKeys.self)
                #expect(
                    throws: DecodingError.self,
                    performing: {
                        try container.decode(Double.self, forKey: .hello)
                    })
            }

            @Test func decodeDoubleFromInt() throws {
                let decoder = _OracleJSONDecoder(
                    codingPath: [],
                    userInfo: [:],
                    value: .container(["hello": .int(1)])
                )
                enum CodingKeys: CodingKey {
                    case hello
                }

                let container = try decoder.container(keyedBy: CodingKeys.self)
                #expect(try container.decode(Double.self, forKey: .hello) == 1.0)
            }

            @Test func decodeDoubleFromFloat() throws {
                let decoder = _OracleJSONDecoder(
                    codingPath: [],
                    userInfo: [:],
                    value: .container(["hello": .float(1.0)])
                )
                enum CodingKeys: CodingKey {
                    case hello
                }

                let container = try decoder.container(keyedBy: CodingKeys.self)
                #expect(try container.decode(Double.self, forKey: .hello) == 1.0)
            }

            @Test func decodeDouble() throws {
                let decoder = _OracleJSONDecoder(
                    codingPath: [],
                    userInfo: [:],
                    value: .container(["hello": .double(1.0)])
                )
                enum CodingKeys: CodingKey {
                    case hello
                }

                let container = try decoder.container(keyedBy: CodingKeys.self)
                #expect(try container.decode(Double.self, forKey: .hello) == 1.0)
            }

            @Test func decodeDoubleFromTooLargeInt() throws {
                let decoder = _OracleJSONDecoder(
                    codingPath: [],
                    userInfo: [:],
                    value: .container(["hello": .int(.max)])
                )
                enum CodingKeys: CodingKey {
                    case hello
                }

                let container = try decoder.container(keyedBy: CodingKeys.self)
                #expect(
                    throws: DecodingError.self,
                    performing: {
                        try container.decode(Double.self, forKey: .hello)
                    })
            }

            @Test func decodeFloat() throws {
                let decoder = _OracleJSONDecoder(
                    codingPath: [],
                    userInfo: [:],
                    value: .container(["hello": .float(1.0)])
                )
                enum CodingKeys: CodingKey {
                    case hello
                }

                let container = try decoder.container(keyedBy: CodingKeys.self)
                #expect(try container.decode(Float.self, forKey: .hello) == 1.0)
            }

            @Test func decodeIntFromDouble() throws {
                let decoder = _OracleJSONDecoder(
                    codingPath: [],
                    userInfo: [:],
                    value: .container(["hello": .double(1)])
                )
                enum CodingKeys: CodingKey {
                    case hello
                }

                let container = try decoder.container(keyedBy: CodingKeys.self)
                #expect(try container.decode(Int.self, forKey: .hello) == 1)
            }

            @Test func decodeIntFromPreciseDoubleFails() throws {
                let decoder = _OracleJSONDecoder(
                    codingPath: [],
                    userInfo: [:],
                    value: .container(["hello": .double(1.05)])
                )
                enum CodingKeys: CodingKey {
                    case hello
                }

                let container = try decoder.container(keyedBy: CodingKeys.self)
                #expect(
                    throws: DecodingError.self,
                    performing: {
                        try container.decode(Int.self, forKey: .hello)
                    })
            }

            @Test func decodeIntFromFloat() throws {
                let decoder = _OracleJSONDecoder(
                    codingPath: [],
                    userInfo: [:],
                    value: .container(["hello": .float(1)])
                )
                enum CodingKeys: CodingKey {
                    case hello
                }

                let container = try decoder.container(keyedBy: CodingKeys.self)
                #expect(try container.decode(Int.self, forKey: .hello) == 1)
            }

            @Test func decodeIntFromPreciseFloatFails() throws {
                let decoder = _OracleJSONDecoder(
                    codingPath: [],
                    userInfo: [:],
                    value: .container(["hello": .float(1.05)])
                )
                enum CodingKeys: CodingKey {
                    case hello
                }

                let container = try decoder.container(keyedBy: CodingKeys.self)
                #expect(
                    throws: DecodingError.self,
                    performing: {
                        try container.decode(Int.self, forKey: .hello)
                    })
            }

            @Test func decodeIntFromStringFails() throws {
                let decoder = _OracleJSONDecoder(
                    codingPath: [],
                    userInfo: [:],
                    value: .container(["hello": .string("1")])
                )
                enum CodingKeys: CodingKey {
                    case hello
                }

                let container = try decoder.container(keyedBy: CodingKeys.self)
                #expect(
                    throws: DecodingError.self,
                    performing: {
                        try container.decode(Int.self, forKey: .hello)
                    })
            }

            @Test func decodeInt() throws {
                let decoder = _OracleJSONDecoder(
                    codingPath: [],
                    userInfo: [:],
                    value: .container(["hello": .int(1)])
                )
                enum CodingKeys: CodingKey {
                    case hello
                }

                let container = try decoder.container(keyedBy: CodingKeys.self)
                #expect(try container.decode(Int.self, forKey: .hello) == 1)
            }

            @Test func decodeInt8FromTooLargeInt() throws {
                let decoder = _OracleJSONDecoder(
                    codingPath: [],
                    userInfo: [:],
                    value: .container(["hello": .int(Int(Int8.max) + 1)])
                )
                enum CodingKeys: CodingKey {
                    case hello
                }

                let container = try decoder.container(keyedBy: CodingKeys.self)
                #expect(
                    throws: DecodingError.self,
                    performing: {
                        try container.decode(Int8.self, forKey: .hello)
                    })
            }

            @Test func decodeInt8() throws {
                let decoder = _OracleJSONDecoder(
                    codingPath: [],
                    userInfo: [:],
                    value: .container(["hello": .int(1)])
                )
                enum CodingKeys: CodingKey {
                    case hello
                }

                let container = try decoder.container(keyedBy: CodingKeys.self)
                #expect(try container.decode(Int8.self, forKey: .hello) == 1)
            }

            @Test func decodeInt16() throws {
                let decoder = _OracleJSONDecoder(
                    codingPath: [],
                    userInfo: [:],
                    value: .container(["hello": .int(1)])
                )
                enum CodingKeys: CodingKey {
                    case hello
                }

                let container = try decoder.container(keyedBy: CodingKeys.self)
                #expect(try container.decode(Int16.self, forKey: .hello) == 1)
            }

            @Test func decodeInt32() throws {
                let decoder = _OracleJSONDecoder(
                    codingPath: [],
                    userInfo: [:],
                    value: .container(["hello": .int(1)])
                )
                enum CodingKeys: CodingKey {
                    case hello
                }

                let container = try decoder.container(keyedBy: CodingKeys.self)
                #expect(try container.decode(Int32.self, forKey: .hello) == 1)
            }

            @Test func decodeInt64() throws {
                let decoder = _OracleJSONDecoder(
                    codingPath: [],
                    userInfo: [:],
                    value: .container(["hello": .int(1)])
                )
                enum CodingKeys: CodingKey {
                    case hello
                }

                let container = try decoder.container(keyedBy: CodingKeys.self)
                #expect(try container.decode(Int64.self, forKey: .hello) == 1)
            }

            @Test func decodeUInt() throws {
                let decoder = _OracleJSONDecoder(
                    codingPath: [],
                    userInfo: [:],
                    value: .container(["hello": .int(1)])
                )
                enum CodingKeys: CodingKey {
                    case hello
                }

                let container = try decoder.container(keyedBy: CodingKeys.self)
                #expect(try container.decode(UInt.self, forKey: .hello) == 1)
            }

            @Test func decodeUInt8() throws {
                let decoder = _OracleJSONDecoder(
                    codingPath: [],
                    userInfo: [:],
                    value: .container(["hello": .int(1)])
                )
                enum CodingKeys: CodingKey {
                    case hello
                }

                let container = try decoder.container(keyedBy: CodingKeys.self)
                #expect(try container.decode(UInt8.self, forKey: .hello) == 1)
            }

            @Test func decodeUInt16() throws {
                let decoder = _OracleJSONDecoder(
                    codingPath: [],
                    userInfo: [:],
                    value: .container(["hello": .int(1)])
                )
                enum CodingKeys: CodingKey {
                    case hello
                }

                let container = try decoder.container(keyedBy: CodingKeys.self)
                #expect(try container.decode(UInt16.self, forKey: .hello) == 1)
            }

            @Test func decodeUInt32() throws {
                let decoder = _OracleJSONDecoder(
                    codingPath: [],
                    userInfo: [:],
                    value: .container(["hello": .int(1)])
                )
                enum CodingKeys: CodingKey {
                    case hello
                }

                let container = try decoder.container(keyedBy: CodingKeys.self)
                #expect(try container.decode(UInt32.self, forKey: .hello) == 1)
            }

            @Test func decodeUInt64() throws {
                let decoder = _OracleJSONDecoder(
                    codingPath: [],
                    userInfo: [:],
                    value: .container(["hello": .int(1)])
                )
                enum CodingKeys: CodingKey {
                    case hello
                }

                let container = try decoder.container(keyedBy: CodingKeys.self)
                #expect(try container.decode(UInt64.self, forKey: .hello) == 1)
            }

            @Test func decodeDate() throws {
                let decoder = _OracleJSONDecoder(
                    codingPath: [],
                    userInfo: [:],
                    value: .container([
                        "hello": .date(.init(timeIntervalSince1970: 500))
                    ])
                )
                enum CodingKeys: CodingKey {
                    case hello
                }

                let container = try decoder.container(keyedBy: CodingKeys.self)
                #expect(
                    try container.decode(Date.self, forKey: .hello)
                        == .init(timeIntervalSince1970: 500)
                )
            }

            @Test func decodeIntervalDS() throws {
                let decoder = _OracleJSONDecoder(
                    codingPath: [],
                    userInfo: [:],
                    value: .container([
                        "hello": .intervalDS(15.0)
                    ])
                )
                enum CodingKeys: CodingKey {
                    case hello
                }

                let container = try decoder.container(keyedBy: CodingKeys.self)
                #expect(
                    try container.decode(IntervalDS.self, forKey: .hello) == 15.0
                )
            }

            @Test func decodeVectorInt8() throws {
                let decoder = _OracleJSONDecoder(
                    codingPath: [],
                    userInfo: [:],
                    value: .container([
                        "hello": .vectorInt8([1, 2, 3])
                    ])
                )
                enum CodingKeys: CodingKey {
                    case hello
                }

                let container = try decoder.container(keyedBy: CodingKeys.self)
                #expect(
                    try container.decode(OracleVectorInt8.self, forKey: .hello) == [1, 2, 3]
                )
            }

            @Test func decodeVectorFloat32() throws {
                let decoder = _OracleJSONDecoder(
                    codingPath: [],
                    userInfo: [:],
                    value: .container([
                        "hello": .vectorFloat32([1.1, 2.2, 3.3])
                    ])
                )
                enum CodingKeys: CodingKey {
                    case hello
                }

                let container = try decoder.container(keyedBy: CodingKeys.self)
                #expect(
                    try container.decode(OracleVectorFloat32.self, forKey: .hello) == [
                        1.1, 2.2, 3.3,
                    ]
                )
            }

            @Test func decodeVectorFloat64() throws {
                let decoder = _OracleJSONDecoder(
                    codingPath: [],
                    userInfo: [:],
                    value: .container([
                        "hello": .vectorFloat64([1.1, 2.2, 3.3])
                    ])
                )
                enum CodingKeys: CodingKey {
                    case hello
                }

                let container = try decoder.container(keyedBy: CodingKeys.self)
                #expect(
                    try container.decode(OracleVectorFloat64.self, forKey: .hello) == [
                        1.1, 2.2, 3.3,
                    ]
                )
            }

            @Test func decodeGeneric() throws {
                let decoder = _OracleJSONDecoder(
                    codingPath: [],
                    userInfo: [:],
                    value: .container(["hello": .string("foo")])
                )
                enum CodingKeys: CodingKey {
                    case hello
                }

                let container = try decoder.container(keyedBy: CodingKeys.self)
                func decode<T: Decodable>(_: T.Type) throws -> T {
                    try container.decode(T.self, forKey: .hello)
                }
                #expect(try decode(String.self) == "foo")
            }

            @Test func decodeNotExistingNestedKeyFails() throws {
                let decoder = _OracleJSONDecoder(
                    codingPath: [],
                    userInfo: [:],
                    value: .container(["hello": .string("there")])
                )
                struct Object: Decodable {
                    struct Nested: Decodable {
                        let hello: String
                    }
                    let nested: Nested
                    enum CodingKeys: CodingKey {
                        case nested
                    }
                }
                #expect(
                    throws: DecodingError.self,
                    performing: {
                        try Object(from: decoder)
                    })
            }

            @Test func decodeNestedKey() throws {
                let decoder = _OracleJSONDecoder(
                    codingPath: [],
                    userInfo: [:],
                    value: .container(["nested": .container(["hello": .string("there")])])
                )
                struct Object: Decodable, Equatable {
                    struct Nested: Decodable, Equatable {
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
                #expect(try Object(from: decoder) == .init(nested: .init(hello: "there")))
            }

            @Test func getNestedContainer() throws {
                let decoder = _OracleJSONDecoder(
                    codingPath: [],
                    userInfo: [:],
                    value: .container(["nested": .container(["hello": .string("there")])])
                )
                enum CodingKeys: CodingKey {
                    case nested
                    enum Nested: CodingKey {
                        case hello
                    }
                }
                let container = try decoder.container(keyedBy: CodingKeys.self)
                let nested = try container.nestedContainer(
                    keyedBy: CodingKeys.Nested.self, forKey: .nested)
                #expect(try nested.decode(String.self, forKey: .hello) == "there")
            }

            @Test func getNestedUnkeyedContainer() throws {
                let decoder = _OracleJSONDecoder(
                    codingPath: [],
                    userInfo: [:],
                    value: .container(["nested": .array([.string("there")])])
                )
                enum CodingKeys: CodingKey {
                    case nested
                }
                let container = try decoder.container(keyedBy: CodingKeys.self)
                var nested = try container.nestedUnkeyedContainer(forKey: .nested)
                #expect(try nested.decode(String.self) == "there")
            }

            @Test func getSuperDecoder() throws {
                let decoder = _OracleJSONDecoder(
                    codingPath: [],
                    userInfo: [:],
                    value: .container(["nested": .container(["hello": .string("there")])])
                )
                enum CodingKeys: CodingKey {
                    case nested
                }
                let container = try decoder.container(keyedBy: CodingKeys.self)
                #expect(
                    throws: Never.self,
                    performing: {
                        _ = try container.superDecoder()
                        _ = try container.superDecoder(forKey: .nested)
                    })
            }
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
