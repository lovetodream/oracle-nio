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

import Logging
import NIOCore

/// A datatype that maps to Oracle's `SYS_REFCURSOR`.
///
/// It holds a reference to a cursor within a Oracle database connection.
/// The cursor can be executed once to receive it's results.
public struct Cursor: ~Copyable {
    public let id: UInt16
    public var columns: OracleColumns {
        OracleColumns(underlying: self.describeInfo.columns)
    }

    let isQuery: Bool
    let describeInfo: DescribeInfo

    /// Executes the cursor and returns its result.
    ///
    /// - Note: The cursor has to be executed on the connection it was created on.
    ///         It cannot be executed more than once.
    public consuming func execute(
        on connection: OracleConnection,
        logger: Logger = OracleConnection.noopLogger
    ) async throws -> OracleRowSequence {
        try await connection.execute(cursor: self, logger: logger)
    }
}

extension Cursor: OracleEncodable {
    @inlinable
    public func _encodeRaw(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext
    ) {
        // The length of the parameter value, in bytes (this count does not
        // include itself). Can be zero.
        let lengthIndex = buffer.writerIndex
        buffer.writeInteger(0, as: UInt8.self)
        let startIndex = buffer.writerIndex
        // The value of the parameter, in the format indicated by the associated
        // format code.
        self.encode(into: &buffer, context: context)

        // overwrite the empty length, with the real value.
        buffer.setInteger(
            numericCast(buffer.writerIndex - startIndex),
            at: lengthIndex, as: UInt8.self
        )
    }

    public var oracleType: OracleDataType { Self.defaultOracleType }

    public var size: UInt32 { UInt32(self.oracleType.defaultSize) }

    public static var isArray: Bool { false }
    public var arrayCount: Int? { nil }
    public var arraySize: Int? { Self.isArray ? 1 : nil }

    public static var defaultOracleType: OracleDataType { .cursor }


    public func encode(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext
    ) {
        if self.id == 0 {
            buffer.writeInteger(UInt8(0))
        } else {
            buffer.writeUB4(UInt32(self.id))
        }
    }
}

extension Cursor: OracleNonCopyableDecodable {
    @inlinable
    public static func _decodeRaw(
        from buffer: inout ByteBuffer?,
        type: OracleDataType,
        context: OracleDecodingContext
    ) throws -> Self {
        guard var buffer else {
            throw OracleDecodingError.Code.missingData
        }
        return try self.init(from: &buffer, type: type, context: context)
    }

    public init(
        from buffer: inout ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext
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
