//===----------------------------------------------------------------------===//
//
// This source file is part of the OracleNIO open source project
//
// Copyright (c) 2024 Timo Zacherl and the OracleNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIOCore

/// A datatype that maps to Oracle's `SYS_REFCURSOR`.
///
/// It holds a reference to a cursor within a Oracle database connection.
/// The cursor can be executed once to receive it's results.
public struct Cursor {
    public let id: UInt16
    public var columns: [OracleColumn] { self.describeInfo.columns }

    let isQuery: Bool
    let describeInfo: DescribeInfo

    /// Executes the cursor and returns its result.
    ///
    /// - Note: The cursor has to be executed on the connection it was created on.
    ///         It cannot be executed more than once.
    public func execute(
        on connection: OracleConnection
    ) async throws -> OracleRowSequence {
        try await connection.execute(cursor: self)
    }
}

extension Cursor: OracleEncodable {
    public var oracleType: OracleDataType { .cursor }

    public func encode<JSONEncoder: OracleJSONEncoder>(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext<JSONEncoder>
    ) {
        if self.id == 0 {
            buffer.writeInteger(UInt8(0))
        } else {
            buffer.writeUB4(UInt32(self.id))
        }
    }
}

extension Cursor: OracleDecodable {
    public init<JSONDecoder: OracleJSONDecoder>(
        from buffer: inout ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext<JSONDecoder>
    ) throws {
        switch type {
        case .cursor:
            let capabilities = try Capabilities(from: &buffer)
            let describeInfo = try DescribeInfo._decode(
                from: &buffer, context: .init(capabilities: capabilities)
            )
            let id = try buffer.throwingReadUB2()
            self = Cursor(
                id: id,
                isQuery: true,
                describeInfo: describeInfo
            )
        default:
            throw OracleDecodingError.Code.typeMismatch
        }
    }
}
