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

import NIOCore

extension Bool: OracleEncodable {
    public var oracleType: OracleDataType { .boolean }

    public func encode<JSONEncoder: OracleJSONEncoder>(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext<JSONEncoder>
    ) {
        if self {
            buffer.writeInteger(UInt16(0x0101))
        } else {
            buffer.writeInteger(UInt8(0x00))
        }
    }
}

extension Bool: OracleDecodable {
    public init<JSONDecoder: OracleJSONDecoder>(
        from buffer: inout ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext<JSONDecoder>
    ) throws {
        switch type {
        case .boolean:
            guard
                let byte = buffer.getInteger(
                    at: buffer.readableBytes - 1, as: UInt8.self
                )
            else {
                throw OracleDecodingError.Code.missingData
            }
            self = byte == 1
        default:
            throw OracleDecodingError.Code.typeMismatch
        }
    }
}
