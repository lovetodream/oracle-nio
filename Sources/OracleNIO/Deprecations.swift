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

// TODO: remove them all before 1.0.0

import struct Logging.Logger

@_documentation(visibility:internal)
@available(*, deprecated, renamed: "OracleStatement")
public typealias OracleQuery = OracleStatement

@_documentation(visibility:internal)
@available(*, deprecated, renamed: "StatementOptions")
public typealias QueryOptions = StatementOptions

extension OracleSQLError.Code {
    @_documentation(visibility:internal)
    @available(*, deprecated, renamed: "statementCancelled")
    public static let queryCancelled = OracleSQLError.Code.statementCancelled
}

extension OracleSQLError {
    @_documentation(visibility:internal)
    @available(*, deprecated, renamed: "statement", message: "will be removed before 1.0.0")
    public internal(set) var query: OracleQuery? {
        get { self.statement }
        set {
            self.statement = newValue
        }
    }
}

extension OracleConnection {
    @_documentation(visibility:internal)
    @available(*, deprecated, renamed: "execute(_:options:logger:file:line:)")
    @discardableResult
    public func query(
        _ query: OracleQuery,
        options: QueryOptions = .init(),
        logger: Logger? = nil,
        file: String = #fileID, line: Int = #line
    ) async throws -> OracleRowSequence {
        try await self.execute(
            query,
            options: options,
            logger: logger,
            file: file,
            line: line
        )
    }
}
