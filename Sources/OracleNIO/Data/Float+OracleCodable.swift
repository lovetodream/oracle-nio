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

extension Float: OracleEncodable {
    @inlinable
    public static var defaultOracleType: OracleDataType { .binaryFloat }

    @inlinable
    public func encode(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext
    ) {
        var b0: UInt8
        var b1: UInt8
        var b2: UInt8
        var b3: UInt8
        let allBits = self.bitPattern
        b3 = UInt8(allBits & 0xff)
        b2 = UInt8((allBits >> 8) & 0xff)
        b1 = UInt8((allBits >> 16) & 0xff)
        b0 = UInt8((allBits >> 24) & 0xff)
        if b0 & 0x80 == 0 {
            b0 = b0 | 0x80
        } else {
            b0 = ~b0
            b1 = ~b1
            b2 = ~b2
            b3 = ~b3
        }
        buffer.writeBytes([b0, b1, b2, b3])
    }
}

extension Float: OracleDecodable {
    @inlinable
    public init(
        from buffer: inout ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext
    ) throws {
        switch type {
        case .number, .binaryInteger:
            self = try OracleNumeric.parseFloat(from: &buffer)
        case .binaryFloat:
            self = try OracleNumeric.parseBinaryFloat(from: &buffer)
        default:
            throw OracleDecodingError.Code.typeMismatch
        }
    }
}
