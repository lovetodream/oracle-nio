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

public import NIOCore

#if canImport(FoundationEssentials)
    import FoundationEssentials
#else
    import Foundation
#endif

extension String: OracleEncodable {
    @inlinable
    public func encode(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext
    ) {
        ByteBuffer(string: self)._encodeRaw(into: &buffer, context: context)
    }

    @inlinable
    public func _encodeRaw(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext
    ) {
        self.encode(into: &buffer, context: context)
    }

    @inlinable
    public static var defaultOracleType: OracleDataType { .varchar }

    @inlinable
    public var size: UInt32 {
        // empty strings have a length of 1
        // (they're basically the same as null in a oracle db)
        .init(self.count >= 1 ? self.count : 1)
    }
}

extension String: OracleDecodable {
    @inlinable
    static public func _decodeRaw(
        from buffer: inout ByteBuffer?,
        type: OracleDataType,
        context: OracleDecodingContext
    ) throws -> String {
        // because oracle doesn't differentiate between null and empty strings
        // we have to use the internal imp
        guard var buffer else {
            return ""
        }
        return try self.init(from: &buffer, type: type, context: context)
    }

    @inlinable
    public init(
        from buffer: inout ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext
    ) throws {
        switch type {
        case .varchar, .char, .long, .nVarchar, .longNVarchar, .longRAW:
            if type.csfrm == Constants.TNS_CS_IMPLICIT || type.csfrm == 0 {
                self = buffer.readString(length: buffer.readableBytes)!
            } else {
                let byteCount = buffer.readableBytes
                guard byteCount % 2 == 0 else {
                    throw OracleDecodingError.Code.failure
                }
                var utf16 = [Unicode.UTF16.CodeUnit](repeating: 0, count: byteCount / 2)
                buffer.readWithUnsafeReadableBytes { rawPointer in
                    for i in 0..<utf16.count {
                        utf16[i] = UInt16(
                            bigEndian: rawPointer.loadUnaligned(
                                fromByteOffset: i * 2, as: UInt16.self
                            )
                        )
                    }
                    return byteCount
                }
                self = String(decoding: utf16, as: UTF16.self)
            }
        case .rowID:
            self = try RowID(from: &buffer, type: type, context: context)
                .description
        default:
            throw OracleDecodingError.Code.typeMismatch
        }
    }
}
