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

/// An intermediate type to encode and decode `JSON` columns
/// to and from the Oracle Wire Format.
///
/// Use ``init(_:)`` to create a ``OracleJSON`` from a `Codable` type and use it as a
/// bind variable in ``OracleStatement``s.
///
/// ```swift
/// struct MyCodable: Codable {
///     var foo: String
/// }
/// let oracleJSON = OracleJSON(MyCodable(foo: "bar"))
/// try await connection.execute("INSERT INTO my_json_table (id, jsonval) VALUES (1, \(oracleJSON))")
/// let stream = try await connection.execute("SELECT jsonval FROM my_json_table WHERE id = 1")
/// for try await (dbValue) in stream.decode(OracleJSON<MyCodable>.self) {
///     print(dbValue.foo == oracleJSON.foo)
/// }
/// ```
public struct OracleJSON<Value: Sendable>: Sendable {
    public let value: Value
}
