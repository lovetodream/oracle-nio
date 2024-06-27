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

import struct Foundation.UUID

extension UUID: OracleDecodable {
    public init<JSONDecoder: OracleJSONDecoder>(
        from buffer: inout ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext<JSONDecoder>
    ) throws {
        switch type {
        case .raw, .longRAW:
            guard let uuid = buffer.readUUIDBytes() else {
                throw OracleDecodingError.Code.failure
            }
            self = uuid
        case .varchar, .long:
            guard buffer.readableBytes == 36 else {
                throw OracleDecodingError.Code.failure
            }

            guard let uuid = buffer.readString(length: 36).flatMap({ UUID(uuidString: $0) }) else {
                throw OracleDecodingError.Code.failure
            }
            self = uuid
        default:
            throw OracleDecodingError.Code.typeMismatch
        }
    }
}
