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

extension Optional {
    /// Gets the value contained in an optional.
    ///
    /// - Parameter error: The error to throw if the optional is `nil`.
    /// - Returns: The value contained in the optional.
    /// - Throws: The error passed in if the optional is `nil`.
    func value(or error: Error) throws -> Wrapped {
        switch self {
        case .some(let value): return value
        case .none: throw error
        }
    }
}
