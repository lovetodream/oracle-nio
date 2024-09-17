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

/// OracleJSON is an intermediate type to decode `JSON` columns from the Oracle Wire Format.
///
/// Use ``decode(as:)`` to decode an actual Swift type you can work with.
public struct OracleJSON<Value: Sendable>: Sendable {
    public let value: Value
}
