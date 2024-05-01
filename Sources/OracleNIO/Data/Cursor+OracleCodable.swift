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

public struct Cursor {
    public let id: UInt16
    let isQuery: Bool
    let requiresFullExecute: Bool
    let moreRowsToFetch: Bool

    // fetchArraySize = QueryOptions.arraySize + QueryOptions.prefetchRows
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
            let id = try buffer.throwingReadUB2()
            self = Cursor(
                id: id,
                isQuery: true,
                requiresFullExecute: true,
                moreRowsToFetch: true
            )
        default:
            throw OracleDecodingError.Code.typeMismatch
        }
    }
}
