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

/// A backend row description message.
@usableFromInline
struct DescribeInfo: OracleBackendMessage.PayloadDecodable, Sendable, Hashable {
    @usableFromInline
    var columns: [OracleColumn]

    static func decode(
        from buffer: inout ByteBuffer,
        context: OracleBackendMessageDecoder.Context
    ) throws -> DescribeInfo {
        buffer.skipRawBytesChunked()
        return try self._decode(from: &buffer, context: context)
    }

    static func _decode(
        from buffer: inout ByteBuffer,
        context: OracleBackendMessageDecoder.Context
    ) throws -> DescribeInfo {
        buffer.skipUB4()  // max row size
        let columnCount = try buffer.throwingReadUB4()
        context.columnsCount = Int(columnCount)

        if columnCount > 0 {
            buffer.moveReaderIndex(forwardBy: 1)
        }

        var result = [OracleColumn]()
        result.reserveCapacity(Int(columnCount))

        for _ in 0..<columnCount {
            let field = try OracleColumn.decode(from: &buffer, context: context)
            result.append(field)
        }

        if try buffer.throwingReadUB4() > 0 {
            buffer.skipRawBytesChunked()  // current date
        }
        buffer.skipUB4()  // dcbflag
        buffer.skipUB4()  // dcbmdbz
        buffer.skipUB4()  // dcbmnpr
        buffer.skipUB4()  // dcbmxpr
        if try buffer.throwingReadUB4() > 0 {
            buffer.skipRawBytesChunked()  // dcbqcky
        }

        return DescribeInfo(columns: result)
    }
}

extension OracleColumn: OracleBackendMessage.PayloadDecodable {
    static func decode(
        from buffer: inout ByteBuffer,
        context: OracleBackendMessageDecoder.Context
    ) throws -> OracleColumn {
        let dataType = try buffer.throwingReadInteger(as: UInt8.self)
        buffer.moveReaderIndex(forwardBy: 1)  // flags
        let precision = try buffer.throwingReadInteger(as: Int8.self)
        let scale = try Int16(buffer.throwingReadInteger(as: Int8.self))
        let bufferSize = try buffer.throwingReadUB4()
        buffer.skipUB4()  // max number of array elements
        buffer.skipUB8()  // cont flags

        let oidByteCount = try buffer.throwingReadUB4()  // OID
        if oidByteCount > 0 {
            // oid, only relevant for intNamed
            _ = try buffer.readOracleSpecificLengthPrefixedSlice()
        }

        buffer.skipUB2()  // version
        buffer.skipUB2()  // character set id

        let csfrm = try buffer.throwingReadInteger(as: UInt8.self)
        // character set form
        let dbType = try OracleDataType.fromORATypeAndCSFRM(
            typeNumber: dataType, csfrm: csfrm
        )
        guard dbType._oracleType != nil else {
            throw
                OraclePartialDecodingError
                .fieldNotDecodable(type: OracleDataType.self)
        }

        var size = try buffer.throwingReadUB4()
        if dataType == _TNSDataType.raw.rawValue {
            size = bufferSize
        }

        if context.capabilities.ttcFieldVersion >= Constants.TNS_CCAP_FIELD_VERSION_12_2 {
            buffer.skipUB4()  // oaccolid
        }

        let nullsAllowed =
            try buffer.throwingReadInteger(as: UInt8.self) != 0

        buffer.moveReaderIndex(forwardBy: 1)  // v7 length of name

        guard try buffer.throwingReadUB4() > 0 else {
            throw OraclePartialDecodingError.fieldNotDecodable(type: String.self)
        }
        let name = try buffer.readString()

        let typeSchema: String? =
            if try buffer.throwingReadUB4() > 0 {
                try buffer.readString()  // current schema name, for intNamed
            } else { nil }
        let typeName: String? =
            if try buffer.throwingReadUB4() > 0 {
                try buffer.readString()  // name of intNamed
            } else { nil }

        buffer.skipUB2()  // column position
        buffer.skipUB4()  // uds flag

        var domainSchema: String?
        var domainName: String?
        if context.capabilities.ttcFieldVersion >= Constants.TNS_CCAP_FIELD_VERSION_23_1 {
            if try buffer.throwingReadUB4() > 0 {
                domainSchema = try buffer.readString()
            }
            if try buffer.throwingReadUB4() > 0 {
                domainName = try buffer.readString()
            }
        }

        var annotations: [String: String] = [:]
        if context.capabilities.ttcFieldVersion >= Constants.TNS_CCAP_FIELD_VERSION_23_1_EXT_3 {
            let annotationsCount = try buffer.throwingReadUB4()
            if annotationsCount > 0 {
                buffer.moveReaderIndex(forwardBy: 1)
                let actualCount = try buffer.throwingReadUB4()
                buffer.moveReaderIndex(forwardBy: 1)
                for _ in 0..<actualCount {
                    buffer.skipUB4()  // length of key
                    let key = try buffer.readString()
                    let valueLength = try buffer.throwingReadUB4()
                    let value = if valueLength > 0 { try buffer.readString() } else { "" }
                    annotations[key] = value
                    buffer.skipUB4()  // flags
                }
                buffer.skipUB4()  // flags
            }
        }

        var vectorDimensions: UInt32?
        var vectorFormat: UInt8?
        if context.capabilities.ttcFieldVersion >= Constants.TNS_CCAP_FIELD_VERSION_23_4 {
            vectorDimensions = try buffer.throwingReadUB4()
            vectorFormat = try buffer.throwingReadInteger(as: UInt8.self)
            let vectorFlags = try buffer.throwingReadInteger(as: UInt8.self)
            if (vectorFlags & Constants.VECTOR_META_FLAG_FLEXIBLE_DIM) != 0 {
                vectorDimensions = nil
            }
        }

        return .init(
            name: name, dataType: dbType, dataTypeSize: size,
            precision: Int16(precision), scale: scale,
            bufferSize: bufferSize, nullsAllowed: nullsAllowed,
            typeScheme: typeSchema, typeName: typeName,
            domainSchema: domainSchema, domainName: domainName,
            annotations: annotations, vectorDimensions: vectorDimensions,
            vectorFormat: vectorFormat
        )
    }
}
