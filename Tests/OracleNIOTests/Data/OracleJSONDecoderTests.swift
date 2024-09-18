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
            #expect(performing: {
                try OracleJSONDecoder().decode([String: String].self, from: .array([.string("foo")]))
            }, throws: { error in
                let error = try #require(error as? DecodingError)
                switch error {
                case .typeMismatch:
                    return true
                default:
                    return false
                }
            })
        }

        @Test func decodingArrayFromObjectFails() throws {
            #expect(performing: {
                try OracleJSONDecoder().decode([String].self, from: .container(["foo": .string("bar")]))
            }, throws: { error in
                let error = try #require(error as? DecodingError)
                switch error {
                case .typeMismatch:
                    return true
                default:
                    return false
                }
            })
        }

        @Test func decodeString() throws {
            let value = try OracleJSONDecoder().decode(String.self, from: .string("foo"))
            #expect(value == "foo")
        }
    }
#endif
