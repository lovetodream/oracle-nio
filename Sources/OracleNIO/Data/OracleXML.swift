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

/// A type to decode `XMLTYPE` objects from an Oracle server.
///
/// Use ``description`` for a textual xml representation.
public struct OracleXML: Sendable {
    @usableFromInline
    enum Value: Sendable {
        case string(String)
    }
    @usableFromInline
    let value: Value

    @inlinable
    init(from buffer: inout ByteBuffer) throws {
        _ = try Self.readHeader(from: &buffer)
        buffer.moveReaderIndex(forwardBy: 1)  // xml version
        let xmlFlag = try buffer.throwingReadInteger(as: UInt32.self)
        if (xmlFlag & Constants.TNS_XML_TYPE_FLAG_SKIP_NEXT_4) != 0 {
            buffer.moveReaderIndex(forwardBy: 4)
        }
        var slice = buffer.slice()
        if (xmlFlag & Constants.TNS_XML_TYPE_STRING) != 0 {
            self.value = .string(slice.readString(length: slice.readableBytes).unsafelyUnwrapped)
        } else if (xmlFlag & Constants.TNS_XML_TYPE_LOB) != 0 {
            throw OracleDecodingError.Code.typeMismatch
        } else {
            // unexpected xml type flag
            throw OracleDecodingError.Code.failure
        }
    }

    @inlinable
    static func readHeader(from buffer: inout ByteBuffer) throws -> (flags: UInt8, version: UInt8) {
        let flags = try buffer.throwingReadInteger(as: UInt8.self)
        let version = try buffer.throwingReadInteger(as: UInt8.self)
        try skipLength(from: &buffer)
        if (flags & Constants.TNS_OBJ_NO_PREFIX_SEG) != 0 {
            return (flags, version)
        }
        let prefixSegmentLength = try self.readLength(from: &buffer)
        buffer.moveReaderIndex(forwardBy: Int(prefixSegmentLength))
        return (flags, version)
    }

    @inlinable
    static func readLength(from buffer: inout ByteBuffer) throws -> UInt32 {
        let shortLength = try buffer.throwingReadInteger(as: UInt8.self)
        if shortLength == Constants.TNS_LONG_LENGTH_INDICATOR {
            return try buffer.throwingReadInteger()
        }
        return UInt32(shortLength)
    }

    @inlinable
    static func skipLength(from buffer: inout ByteBuffer) throws {
        if try buffer.throwingReadInteger(as: UInt8.self) == Constants.TNS_LONG_LENGTH_INDICATOR {
            buffer.moveReaderIndex(forwardBy: 4)
        }
    }
}

extension OracleXML: OracleDecodable {
    @inlinable
    public init(from buffer: inout ByteBuffer, type: OracleDataType, context: OracleDecodingContext) throws {
        var data = try OracleObject(from: &buffer, type: type, context: context).data
        try self.init(from: &data)
    }
}

extension OracleXML: CustomStringConvertible {
    public var description: String {
        switch self.value {
        case .string(let value):
            return value
        }
    }
}
