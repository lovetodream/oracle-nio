//===----------------------------------------------------------------------===//
//
// This source file is part of the OracleNIO open source project
//
// Copyright (c) 2025 Timo Zacherl and the OracleNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
// See CONTRIBUTORS.md for the list of OracleNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

/// A wrapper around the errors that can accur during a transaction.
public struct OracleTransactionError: Error {

    /// The file in which the transaction was started.
    public var file: String
    /// The line in which the transaction was started.
    public var line: Int

    /// The error thrown in the transaction closure.
    public var closureError: Error?

    /// The error thrown while rolling the transaction back. If the ``closureError`` is set,
    /// but the ``rollbackError`` is empty, the rollback was successful.
    ///
    /// If ``rollbackError`` is set, the rollback failed.
    public var rollbackError: Error?

    /// The error thrown while commiting the transaction.
    public var commitError: Error?
}
