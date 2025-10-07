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

import NIOCore

@usableFromInline
struct OracleObject: OracleDecodable {
    @usableFromInline
    let typeOID: ByteBuffer
    @usableFromInline
    let oid: ByteBuffer
    @usableFromInline
    let snapshot: ByteBuffer
    @usableFromInline
    let data: ByteBuffer

    @inlinable
    init(
        typeOID: ByteBuffer,
        oid: ByteBuffer,
        snapshot: ByteBuffer,
        data: ByteBuffer
    ) {
        self.typeOID = typeOID
        self.oid = oid
        self.snapshot = snapshot
        self.data = data
    }

    @inlinable
    init(
        from buffer: inout ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext
    ) throws {
        switch type {
        case .object:
            let typeOID =
                if try buffer.throwingReadUB4() > 0 {
                    try buffer.throwingReadOracleSpecificLengthPrefixedSlice()
                } else { ByteBuffer() }
            let oid =
                if try buffer.throwingReadUB4() > 0 {
                    try buffer.throwingReadOracleSpecificLengthPrefixedSlice()
                } else { ByteBuffer() }
            let snapshot =
                if try buffer.throwingReadUB4() > 0 {
                    try buffer.throwingReadOracleSpecificLengthPrefixedSlice()
                } else { ByteBuffer() }
            buffer.skipUB2()  // version
            let dataLength = try buffer.throwingReadUB4()
            buffer.skipUB2()  // flags
            let data =
                if dataLength > 0 {
                    try buffer.throwingReadOracleSpecificLengthPrefixedSlice()
                } else { ByteBuffer() }
            self.init(typeOID: typeOID, oid: oid, snapshot: snapshot, data: data)
        default:
            throw OracleDecodingError.Code.typeMismatch
        }
    }
}
