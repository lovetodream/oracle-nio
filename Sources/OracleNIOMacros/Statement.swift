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

/// Defines and implements conformance of the OraclePreparedStatement protocol for Structs.
///
/// For example, the following code applies the `Statement` macro to the type `UsersStatement`:
/// ```swift
/// @Statement("SELECT \("id", Int.self), \("name", String.self), \("age", Int.self) FROM users WHERE \(bind: "age", OracleNumber.self) < age")
/// struct UsersStatement {}
/// ```
///
/// You can send Statements to an Oracle Database server
/// with ``OracleConnection/execute(_:options:logger:file:line:)-9uyvp``.
@attached(member, names: arbitrary)
@attached(extension, conformances: OraclePreparedStatement)
public macro Statement(_ statement: _OracleStatementString) =
    #externalMacro(module: "OracleNIOMacrosPlugin", type: "OracleStatementMacro")
