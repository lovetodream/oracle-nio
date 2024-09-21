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

import OracleNIO
import XCTest

final class JSONTests: XCTIntegrationTest {
    let testCompressedJSON: Bool = env("TEST_COMPRESSED_JSON")?.isEmpty == false

    override func setUp() async throws {
        try await super.setUp()
        _ = try? await connection.execute("DROP TABLE TestJsonCols")
        try await connection.execute(
            """
            create table TestJsonCols (
                IntCol                              number(9) not null,
                JsonVarchar                         varchar2(4000) not null,
                JsonClob                            clob not null,
                JsonBlob                            blob not null,
                constraint TestJsonCols_ck_1 check (JsonVarchar is json),
                constraint TestJsonCols_ck_2 check (JsonClob is json),
                constraint TestJsonCols_ck_3 check (JsonBlob is json)
            )
            """)
        try await connection.execute(
            "insert into TestJsonCols values (1, '[1, 2, 3]', '[4, 5, 6]', '[7, 8, 9]')")
        if testCompressedJSON {
            _ = try? await connection.execute("DROP TABLE TestCompressedJson")
            try await connection.execute(
                """
                create table TestCompressedJson (
                    IntCol number(9) not null,
                    JsonCol json not null
                )
                json (JsonCol)
                store as (compress high)
                """)
            try await connection.execute(
                """
                INSERT INTO TestCompressedJson VALUES (
                    1,
                    '{"key": "value", "int": 8, "array": [1, 2, 3], "bool1": true, "bool2": false, "nested": {"float": 1.2, "double": 1.23, "null": null}}'
                )
                """)
        }
    }

    func testFetchJSONColumns() async throws {
        let stream = try await connection.execute(
            "SELECT intcol, jsonvarchar, jsonclob, jsonblob FROM testjsoncols")
        for try await (id, varchar, clob, blob) in stream.decode((Int, String, String, String).self)
        {
            XCTAssertEqual(id, 1)
            XCTAssertEqual(varchar, "[1, 2, 3]")
            XCTAssertEqual(clob, "[4, 5, 6]")
            XCTAssertEqual(blob, "[7, 8, 9]")
        }
    }

    func testCompressedJSON() async throws {
        try XCTSkipIf(!testCompressedJSON)
        let stream = try await connection.execute("SELECT intcol, jsoncol FROM TestCompressedJson")
        for try await (id, json) in stream.decode((Int, OracleJSON<MyJSON>).self) {
            XCTAssertEqual(id, 1)
            XCTAssertEqual(
                json.value,
                MyJSON(
                    key: "value",
                    int: 8,
                    array: [1, 2, 3],
                    bool1: true,
                    bool2: false,
                    nested: .init(float: 1.2, double: 1.23, null: nil)
                )
            )
        }

        struct MyJSON: Decodable, Equatable {
            var key: String
            var int: Int
            var array: [Int]
            var bool1: Bool
            var bool2: Bool
            var nested: Nested

            struct Nested: Decodable, Equatable {
                var float: Float
                var double: Double
                var null: String?
            }
        }
    }

    func testScalarValue() async throws {
        try XCTSkipIf(!testCompressedJSON)
        try await connection.execute(
            #"INSERT INTO TestCompressedJson (intcol, jsoncol) VALUES (2, '"value"')"#)
        let stream = try await connection.execute(
            "SELECT intcol, jsoncol FROM TestCompressedJson WHERE intcol = 2")
        for try await (id, json) in stream.decode((Int, OracleJSON<String>).self) {
            XCTAssertEqual(id, 2)
            XCTAssertEqual(json.value, "value")
        }
    }

    func testArrayValue() async throws {
        try XCTSkipIf(!testCompressedJSON)
        try await connection.execute(
            #"INSERT INTO TestCompressedJson (intcol, jsoncol) VALUES (2, '["value"]')"#)
        let stream = try await connection.execute(
            "SELECT intcol, jsoncol FROM TestCompressedJson WHERE intcol = 2")
        for try await (id, json) in stream.decode((Int, OracleJSON<[String]>).self) {
            XCTAssertEqual(id, 2)
            XCTAssertEqual(json.value, ["value"])
        }
    }

    func testObjectValue() async throws {
        try XCTSkipIf(!testCompressedJSON)
        try await connection.execute(
            #"INSERT INTO TestCompressedJson (intcol, jsoncol) VALUES (2, '{"foo": "bar"}')"#)
        let stream = try await connection.execute(
            "SELECT intcol, jsoncol FROM TestCompressedJson WHERE intcol = 2")
        for try await (id, json) in stream.decode((Int, OracleJSON<Foo>).self) {
            XCTAssertEqual(id, 2)
            XCTAssertEqual(json.value, Foo(foo: "bar"))
        }
        struct Foo: Codable, Equatable {
            let foo: String
        }
    }

    func testArrayOfObjects() async throws {
        try XCTSkipIf(!testCompressedJSON)
        try await connection.execute(
            #"INSERT INTO TestCompressedJson (intcol, jsoncol) VALUES (2, '[{"foo": "bar1"}, {"foo": "bar2"}]')"#
        )
        let stream = try await connection.execute(
            "SELECT intcol, jsoncol FROM TestCompressedJson WHERE intcol = 2")
        for try await (id, json) in stream.decode((Int, OracleJSON<[Foo]>).self) {
            XCTAssertEqual(id, 2)
            XCTAssertEqual(json.value, [Foo(foo: "bar1"), Foo(foo: "bar2")])
        }
        struct Foo: Codable, Equatable {
            let foo: String
        }
    }

    func testInsertion() async throws {
        try XCTSkipIf(!testCompressedJSON)
        struct Foo: Codable, Equatable {
            let foo: String
        }
        try await connection.execute(
            "INSERT INTO TestCompressedJson VALUES (2, \(OracleJSON(Foo(foo: "bar"))))")
        let stream = try await connection.execute(
            "SELECT intcol, jsoncol FROM TestCompressedJson WHERE intcol = 2")
        for try await (id, json) in stream.decode((Int, OracleJSON<Foo>).self) {
            XCTAssertEqual(id, 2)
            XCTAssertEqual(json.value, Foo(foo: "bar"))
        }
    }
}
