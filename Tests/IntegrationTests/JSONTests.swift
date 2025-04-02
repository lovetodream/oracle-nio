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
    import Atomics
    import OracleNIO
    import Testing

    @Suite(.disabled(if: env("SMOKE_TEST_ONLY") == "1")) final class JSONTests: IntegrationTest {
        static let testCompressedJSON: Bool = env("TEST_COMPRESSED_JSON")?.isEmpty == false
        let connection: OracleConnection

        private static let counter = ManagedAtomic(0)

        init() async throws {
            #expect(isLoggingConfigured)
            self.connection = try await OracleConnection.test()
        }

        deinit {
            #expect(throws: Never.self, performing: { try self.connection.syncClose() })
        }

        func runPopulatedJsonTest<R>(_ test: @escaping (OracleConnection, String) async throws -> R) async throws {
            let key = String(Self.counter.wrappingIncrementThenLoad(ordering: .relaxed))
            do {
                try await connection.execute(
                    "DROP TABLE TestJsonCols\(unescaped: key)", logger: .oracleTest
                )
            } catch let error as OracleSQLError {
                // "ORA-00942: table or view does not exist" can be ignored
                #expect(error.serverInfo?.number == 942)
            }

            try await connection.execute(
                """
                CREATE TABLE TestJsonCols\(unescaped: key) (
                    IntCol                              number(9) not null,
                    JsonVarchar                         varchar2(4000) not null,
                    JsonClob                            clob not null,
                    JsonBlob                            blob not null,
                    constraint TestJsonCols\(unescaped: key)_ck_1 check (JsonVarchar is json),
                    constraint TestJsonCols\(unescaped: key)_ck_2 check (JsonClob is json),
                    constraint TestJsonCols\(unescaped: key)_ck_3 check (JsonBlob is json)
                )
                """,
                logger: .oracleTest
            )
            try await connection.execute(
                "INSERT INTO TestJsonCols\(unescaped: key) values (1, '[1, 2, 3]', '[4, 5, 6]', '[7, 8, 9]')"
            )

            await #expect(throws: Never.self, performing: { try await test(connection, "TestJsonCols\(key)") })

            try await connection.execute(
                "DROP TABLE TestJsonCols\(unescaped: key)", logger: .oracleTest
            )
        }

        func runPopulatedCompressedJsonTest<R>(_ test: @escaping (OracleConnection, String) async throws -> R)
            async throws
        {
            let key = String(Self.counter.wrappingIncrementThenLoad(ordering: .relaxed))
            do {
                try await connection.execute(
                    "DROP TABLE TestCompressedJson\(unescaped: key)", logger: .oracleTest
                )
            } catch let error as OracleSQLError {
                // "ORA-00942: table or view does not exist" can be ignored
                #expect(error.serverInfo?.number == 942)
            }

            try await connection.execute(
                """
                CREATE TABLE TestCompressedJson\(unescaped: key) (
                    IntCol number(9) not null,
                    JsonCol json not null
                )
                json (JsonCol)
                store as (compress high)
                """,
                logger: .oracleTest
            )
            try await connection.execute(
                """
                INSERT INTO TestCompressedJson\(unescaped: key) VALUES (
                    1,
                    '{"key": "value", "int": 8, "array": [1, 2, 3], "bool1": true, "bool2": false, "nested": {"float": 1.2, "double": 1.23, "null": null}}'
                )
                """
            )

            await #expect(throws: Never.self, performing: { try await test(connection, "TestCompressedJson\(key)") })

            try await connection.execute(
                "DROP TABLE TestCompressedJson\(unescaped: key)", logger: .oracleTest
            )
        }

        @Test func fetchJSONColumns() async throws {
            try await runPopulatedJsonTest { connection, tableName in
                let stream = try await connection.execute(
                    "SELECT intcol, jsonvarchar, jsonclob, jsonblob FROM \(unescaped: tableName)")
                for try await (id, varchar, clob, blob) in stream.decode((Int, String, String, String).self) {
                    #expect(id == 1)
                    #expect(varchar == "[1, 2, 3]")
                    #expect(clob == "[4, 5, 6]")
                    #expect(blob == "[7, 8, 9]")
                }
            }
        }

        @Test(.enabled(if: Self.testCompressedJSON)) func testCompressedJSON() async throws {
            try await runPopulatedCompressedJsonTest { connection, tableName in
                let stream = try await connection.execute("SELECT intcol, jsoncol FROM \(unescaped: tableName)")
                for try await (id, json) in stream.decode((Int, OracleJSON<MyJSON>).self) {
                    #expect(id == 1)
                    #expect(
                        json.value
                            == MyJSON(
                                key: "value",
                                int: 8,
                                array: [1, 2, 3],
                                bool1: true,
                                bool2: false,
                                nested: .init(float: 1.2, double: 1.23, null: nil)
                            )
                    )
                }
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

        @Test(.enabled(if: Self.testCompressedJSON)) func scalarValue() async throws {
            try await runPopulatedCompressedJsonTest { connection, tableName in
                try await connection.execute(
                    #"INSERT INTO \#(unescaped: tableName) (intcol, jsoncol) VALUES (2, '"value"')"#)
                let stream = try await connection.execute(
                    "SELECT intcol, jsoncol FROM \(unescaped: tableName) WHERE intcol = 2")
                for try await (id, json) in stream.decode((Int, OracleJSON<String>).self) {
                    #expect(id == 2)
                    #expect(json.value == "value")
                }
            }
        }

        @Test(.enabled(if: Self.testCompressedJSON)) func arrayValue() async throws {
            try await runPopulatedCompressedJsonTest { connection, tableName in
                try await connection.execute(
                    #"INSERT INTO \#(unescaped: tableName) (intcol, jsoncol) VALUES (2, '["value"]')"#)
                let stream = try await connection.execute(
                    "SELECT intcol, jsoncol FROM \(unescaped: tableName) WHERE intcol = 2")
                for try await (id, json) in stream.decode((Int, OracleJSON<[String]>).self) {
                    #expect(id == 2)
                    #expect(json.value == ["value"])
                }
            }
        }

        @Test(.enabled(if: Self.testCompressedJSON)) func objectValue() async throws {
            try await runPopulatedCompressedJsonTest { connection, tableName in
                try await connection.execute(
                    #"INSERT INTO \#(unescaped: tableName) (intcol, jsoncol) VALUES (2, '{"foo": "bar"}')"#)
                let stream = try await connection.execute(
                    "SELECT intcol, jsoncol FROM \(unescaped: tableName) WHERE intcol = 2")
                for try await (id, json) in stream.decode((Int, OracleJSON<Foo>).self) {
                    #expect(id == 2)
                    #expect(json.value == Foo(foo: "bar"))
                }
            }
            struct Foo: Codable, Equatable {
                let foo: String
            }
        }

        @Test(.enabled(if: Self.testCompressedJSON)) func arrayOfObjects() async throws {
            try await runPopulatedCompressedJsonTest { connection, tableName in
                try await connection.execute(
                    #"INSERT INTO \#(unescaped: tableName) (intcol, jsoncol) VALUES (2, '[{"foo": "bar1"}, {"foo": "bar2"}]')"#
                )
                let stream = try await connection.execute(
                    "SELECT intcol, jsoncol FROM \(unescaped: tableName) WHERE intcol = 2")
                for try await (id, json) in stream.decode((Int, OracleJSON<[Foo]>).self) {
                    #expect(id == 2)
                    #expect(json.value == [Foo(foo: "bar1"), Foo(foo: "bar2")])
                }
            }
            struct Foo: Codable, Equatable {
                let foo: String
            }
        }

        @Test(.enabled(if: Self.testCompressedJSON)) func insertion() async throws {
            struct Foo: Codable, Equatable {
                let foo: String
            }
            try await runPopulatedCompressedJsonTest { connection, tableName in
                try await connection.execute(
                    "INSERT INTO \(unescaped: tableName) VALUES (2, \(OracleJSON(Foo(foo: "bar"))))")
                let stream = try await connection.execute(
                    "SELECT intcol, jsoncol FROM \(unescaped: tableName) WHERE intcol = 2")
                for try await (id, json) in stream.decode((Int, OracleJSON<Foo>).self) {
                    #expect(id == 2)
                    #expect(json.value == Foo(foo: "bar"))
                }
            }
        }

        @Test(.enabled(if: Self.testCompressedJSON)) func complexJSON() async throws {
            struct Details: Codable {
                let name: String
                let address: Address
                let email: [String]
                let phone: [String]
                let web: [String]
                let openingHours: [OpeningHour]
            }

            struct Address: Codable {
                let city: String
                let street: String
                let zip: String
            }

            struct OpeningHour: Codable {
                let dayOfWeek: String
                let opens: String
                let closes: String

                enum CodingKeys: String, CodingKey {
                    case dayOfWeek = "day_of_week"
                    case opens, closes
                }
            }

            do {
                try await connection.execute("DROP TABLE pharmacies", logger: .oracleTest)
            } catch let error as OracleSQLError {
                // "ORA-00942: table or view does not exist" can be ignored
                #expect(error.serverInfo?.number == 942)
            }

            try await connection.execute("CREATE TABLE pharmacies (details json)", logger: .oracleTest)

            let details = OracleJSON(
                Details(
                    name: "String",
                    address: Address(city: "String", street: "String", zip: "String"),
                    email: ["String"],
                    phone: ["String"],
                    web: ["String"],
                    openingHours: [OpeningHour(dayOfWeek: "Tuesday", opens: "08:00", closes: "18:00")]
                )
            )
            try await connection.execute("INSERT INTO pharmacies (details) VALUES (\(details))", logger: .oracleTest)

            try await connection.execute("DROP TABLE pharmacies", logger: .oracleTest)
        }
    }
#endif
