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

import struct Foundation.Date

// TODO: needs refactoring
struct OSONDecoder {
    var buffer = ByteBuffer()
    var flags: UInt16 = 0
    var fieldIDLength = 0
    var fieldNames = [String]()
    var treeSegPosition = 0

    mutating func decode(_ data: ByteBuffer) throws -> Any? {
        self.buffer = data

        // Parse root header
        guard let header = buffer.readBytes(length: 3) else { return nil }
        if header[0] != Constants.TNS_JSON_MAGIC_BYTE_1
            || header[1] != Constants.TNS_JSON_MAGIC_BYTE_2
            || header[2] != Constants.TNS_JSON_MAGIC_BYTE_3
        {
            throw OracleError.ErrorType.unexpectedData
        }
        let version = try buffer.throwingReadInteger(as: UInt8.self)
        if version != Constants.TNS_JSON_VERSION {
            throw OracleError.ErrorType.osonVersionNotSupported
        }

        // if value is a scalar value, the header is much smaller
        self.flags = buffer.readInteger(as: UInt16.self) ?? 0
        if flags & Constants.TNS_JSON_FLAG_IS_SCALAR != 0 {
            if flags & Constants.TNS_JSON_FLAG_TREE_SEG_UINT32 != 0 {
                buffer.moveReaderIndex(forwardBy: 4)
            } else {
                buffer.moveReaderIndex(forwardBy: 2)
            }
            return try decodeNode()
        }

        // determine the number of field names
        let numberOfFieldNames: UInt32
        if flags & Constants.TNS_JSON_FLAG_NUM_FNAMES_UINT32 != 0 {
            numberOfFieldNames = buffer.readInteger(as: UInt32.self) ?? 0
            fieldIDLength = 4
        } else if flags & Constants.TNS_JSON_FLAG_NUM_FNAMES_UINT16 != 0 {
            let temp16 = buffer.readInteger(as: UInt16.self) ?? 0
            numberOfFieldNames = UInt32(temp16)
            fieldIDLength = 2
        } else {
            let temp8 = try buffer.throwingReadInteger(as: UInt8.self)
            numberOfFieldNames = UInt32(temp8)
            fieldIDLength = 1
        }

        // determine the size of the field names segment
        let fieldNameOffsetsSize: Int
        let fieldNamesSegSize: UInt32
        if flags & Constants.TNS_JSON_FLAG_FNAMES_SEG_UINT32 != 0 {
            fieldNameOffsetsSize = 4
            fieldNamesSegSize = buffer.readInteger(as: UInt32.self) ?? 0
        } else {
            fieldNameOffsetsSize = 2
            let temp16 = buffer.readInteger(as: UInt16.self) ?? 0
            fieldNamesSegSize = UInt32(temp16)
        }

        // determine the size of the tree segment
        let treeSegSize: UInt32
        if flags & Constants.TNS_JSON_FLAG_TREE_SEG_UINT32 != 0 {
            treeSegSize = buffer.readInteger(as: UInt32.self) ?? 0
        } else {
            let temp16 = buffer.readInteger(as: UInt16.self) ?? 0
            treeSegSize = UInt32(temp16)
        }

        // determine the number of "tiny" nodes
        let numberOfTinyNodes = buffer.readInteger(as: UInt16.self)

        // skip the hash id array
        let hashIDSize: Int
        if flags & Constants.TNS_JSON_FLAG_HASH_ID_UINT8 != 0 {
            hashIDSize = 1
        } else if flags & Constants.TNS_JSON_FLAG_HASH_ID_UINT16 != 0 {
            hashIDSize = 2
        } else {
            hashIDSize = 4
        }
        buffer.moveReaderIndex(forwardBy: hashIDSize)

        // skip the field name offsets array for now
        let fieldNameOffsetsPosition = buffer.readerIndex
        buffer.moveReaderIndex(forwardBy: Int(numberOfFieldNames) * fieldNameOffsetsSize)
        let bytes = buffer.readBytes(length: Int(fieldNamesSegSize)) ?? []

        // determine the names of the fields
        buffer.moveReaderIndex(to: fieldNameOffsetsPosition)
        fieldNames = .init(repeating: "", count: Int(numberOfFieldNames))
        for i in 0..<Int(numberOfFieldNames) {
            let offset: UInt32
            if self.flags & Constants.TNS_JSON_FLAG_FNAMES_SEG_UINT32 != 0 {
                offset = buffer.readInteger(as: UInt32.self) ?? 0
            } else {
                let temp16 = buffer.readInteger(as: UInt16.self) ?? 0
                offset = UInt32(temp16)
            }
            let temp8 = bytes[Int(offset)]
            let range = (Int(offset) + 1)...(Int(offset) + Int(UInt32(temp8)))
            let name = Array(bytes[range])
            self.fieldNames[i] = String(cString: name)
        }

        // get tree segment
        buffer.moveReaderIndex(forwardBy: Int(fieldNamesSegSize))
        treeSegPosition = buffer.readerIndex

        return try decodeNode()
    }

    private mutating func decodeNode() throws -> Any? {  // TODO: better return type
        let nodeType = try buffer.throwingReadInteger(as: UInt8.self)
        if nodeType & 0x80 != 0 {
            return try decodeContainerNode(nodeType: nodeType)
        }

        var bytes: ByteBuffer
        switch nodeType {
        case Constants.TNS_JSON_TYPE_NULL:
            return nil
        case Constants.TNS_JSON_TYPE_TRUE:
            return true
        case Constants.TNS_JSON_TYPE_FALSE:
            return false

        // handle fixed length scalars
        case Constants.TNS_JSON_TYPE_DATE, Constants.TNS_JSON_TYPE_TIMESTAMP7:
            bytes = buffer.readSlice(length: 7) ?? .init()
            return try Date(from: &bytes, type: .date, context: .default)
        case Constants.TNS_JSON_TYPE_TIMESTAMP:
            bytes = buffer.readSlice(length: 11) ?? .init()
            return try Date(from: &bytes, type: .timestamp, context: .default)
        case Constants.TNS_JSON_TYPE_TIMESTAMP_TZ:
            bytes = buffer.readSlice(length: 13) ?? .init()
            return try Date(from: &bytes, type: .timestampTZ, context: .default)
        case Constants.TNS_JSON_TYPE_BINARY_FLOAT:
            bytes = buffer.readSlice(length: 4) ?? .init()
            return try Float(
                from: &bytes, type: .binaryFloat, context: .default
            )
        case Constants.TNS_JSON_TYPE_BINARY_DOUBLE:
            bytes = buffer.readSlice(length: 8) ?? .init()
            return try Double(
                from: &bytes, type: .binaryDouble, context: .default
            )
        case Constants.TNS_JSON_TYPE_INTERVAL_DS:
            bytes = buffer.readSlice(length: 11) ?? .init()
            return try IntervalDS(
                from: &bytes, type: .intervalDS, context: .default
            )
        case Constants.TNS_JSON_TYPE_INTERVAL_YM:
            throw OracleError.ErrorType.dbTypeNotSupported

        // handle scalars with lengths stored outside the node itself
        case Constants.TNS_JSON_TYPE_STRING_LENGTH_UINT8:
            let temp8 = try buffer.throwingReadInteger(as: UInt8.self)
            return buffer.readString(length: Int(temp8))
        case Constants.TNS_JSON_TYPE_STRING_LENGTH_UINT16:
            let temp16 = buffer.readInteger(as: UInt16.self) ?? 0
            return buffer.readString(length: Int(temp16))
        case Constants.TNS_JSON_TYPE_STRING_LENGTH_UINT32:
            let temp32 = buffer.readInteger(as: UInt32.self) ?? 0
            return buffer.readString(length: Int(temp32))
        case Constants.TNS_JSON_TYPE_NUMBER_LENGTH_UINT8:
            let length = Int(try buffer.throwingReadInteger(as: UInt8.self))
            var slice = buffer.readSlice(length: length) ?? .init()
            let value: Double = try OracleNumeric.parseFloat(from: &slice)
            return value
        case Constants.TNS_JSON_TYPE_BINARY_LENGTH_UINT16:
            let temp16 = buffer.readInteger(as: UInt16.self) ?? 0
            return temp16
        case Constants.TNS_JSON_TYPE_BINARY_LENGTH_UINT32:
            let temp32 = buffer.readInteger(as: UInt32.self) ?? 0
            return temp32

        default: break
        }

        // handle number/decimal with length stored inside the node itself
        if [0x20, 0x60].contains(nodeType & 0xf0) {
            let temp8 = nodeType & 0x0f
            bytes = buffer.readSlice(length: Int(temp8) + 1) ?? .init()
            return try OracleNumber(
                from: &bytes, type: .number, context: .default
            )
        }

        // handle integer with length stored inside the node itself
        if [0x40, 0x50].contains(nodeType & 0xf0) {
            let temp8 = nodeType & 0x0f
            bytes = buffer.readSlice(length: Int(temp8)) ?? .init()
            return try OracleNumber(
                from: &bytes, type: .number, context: .default
            )
        }

        // handle string with length stored inside the node itself
        if nodeType & 0xe0 == 0 {
            if nodeType == 0 {
                return ""
            }
            return buffer.readString(length: Int(nodeType))
        }

        throw OracleError.ErrorType.osonNodeTypeNotSupported
    }

    private mutating func decodeContainerNode(nodeType: UInt8) throws -> Any? {
        let isObject = nodeType & 0x40 == 0

        // determine the number of children by examining the 4th and 5th most
        // significant bits of the node type; determine the offsets in the tree
        // segment to the field ids array and the value offsets array
        var (numberOfChildren, isShared) = try getNumberOfChildren(
            nodeType: nodeType
        )
        var offsetPosition: Int
        var fieldIDsPosition: Int
        var value: Any?
        if isShared {
            value = [String: Any?]()
            let offset = getOffset(nodeType: nodeType)
            offsetPosition = buffer.readerIndex
            buffer.moveReaderIndex(to: treeSegPosition + Int(offset))
            let temp8 = try buffer.throwingReadInteger(as: UInt8.self)
            (numberOfChildren, isShared) = try getNumberOfChildren(
                nodeType: temp8
            )
            fieldIDsPosition = buffer.readerIndex
        } else if isObject {
            value = [String: Any?]()
            fieldIDsPosition = buffer.readerIndex
            offsetPosition = buffer.readerIndex + fieldIDLength * Int(numberOfChildren)
        } else {
            fieldIDsPosition = 0
            value = [Any?](repeating: nil, count: Int(numberOfChildren))
            offsetPosition = buffer.readerIndex
        }

        // process each of the children
        for i in 0..<numberOfChildren {
            let name: String?
            if isObject {
                buffer.moveReaderIndex(to: fieldIDsPosition)
                if fieldIDLength == 1 {
                    let temp8 = try buffer.throwingReadInteger(as: UInt8.self)
                    name = self.fieldNames[Int(temp8) - 1]
                } else if fieldIDLength == 2 {
                    let temp16 = buffer.readInteger(as: UInt16.self) ?? 0
                    name = self.fieldNames[Int(temp16) - 1]
                } else {
                    let temp32 = buffer.readInteger(as: UInt32.self) ?? 0
                    name = self.fieldNames[Int(temp32) - 1]
                }
                fieldIDsPosition = buffer.readerIndex
            } else {
                name = nil
            }
            buffer.moveReaderIndex(to: offsetPosition)
            let offset = getOffset(nodeType: nodeType)
            offsetPosition = buffer.readerIndex
            buffer.moveReaderIndex(to: treeSegPosition + Int(offset))
            if isObject, let name, var typed = value as? [String: Any?] {
                typed[name] = try decodeNode()
                value = typed
            } else if var typed = value as? [Any?] {
                typed[Int(i)] = try decodeNode()
                value = typed
            }
        }

        return value
    }

    /// Return the number of children the container has. This is determined by
    /// examining the 4th and 5th signficant bits of the node type:
    ///
    ///    00 - number of children is UInt8
    ///    01 - number of children is UInt16
    ///    10 - number of children is UInt32
    ///    11 - field ids are shared with another object whose offset follows
    ///
    /// In the latter case the flag is_shared is set and the number of children
    /// is read by the caller instead as it must examine the offset and then
    /// retain the location for later use.
    mutating func getNumberOfChildren(
        nodeType: UInt8
    ) throws -> (numberOfChildren: UInt32, isShared: Bool) {
        let childrenBits = nodeType & 0x18
        let isShared = childrenBits == 0x18
        let numberOfChildren: UInt32
        if childrenBits == 0 {
            let temp8 = try buffer.throwingReadInteger(as: UInt8.self)
            numberOfChildren = UInt32(temp8)
        } else if childrenBits == 0x08 {
            let temp16 = buffer.readInteger(as: UInt16.self) ?? 0
            numberOfChildren = UInt32(temp16)
        } else if childrenBits == 0x10 {
            numberOfChildren = buffer.readInteger(as: UInt32.self) ?? 0
        } else {
            numberOfChildren = 0
        }
        return (numberOfChildren, isShared)
    }

    /// Return an offset. The offset will be either a 16-bit or 32-bit value
    /// depending on the value of the 3rd significant bit of the node type.
    mutating func getOffset(nodeType: UInt8) -> UInt32 {
        if nodeType & 0x20 != 0 {
            return buffer.readInteger(as: UInt32.self) ?? 0
        }
        return buffer.readInteger(as: UInt16.self).map(UInt32.init(_:)) ?? 0
    }
}
