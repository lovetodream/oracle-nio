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

struct OracleJSONParser {
    var flags: UInt16 = 0
    var fieldIDLength = 0
    var fieldNames = [String]()
    var treeSegPosition = 0
    var relativeOffsets = false

    private init() {}

    static func parse(from buffer: inout ByteBuffer) throws -> OracleJSONStorage {
        var parser = OracleJSONParser()
        return try parser.decode(from: &buffer)
    }

    private mutating func decode(from buffer: inout ByteBuffer) throws -> OracleJSONStorage {

        // Parse root header
        let header = try buffer.throwingReadMultipleIntegers(as: (UInt8, UInt8, UInt8).self)
        if header.0 != Constants.TNS_JSON_MAGIC_BYTE_1
            || header.1 != Constants.TNS_JSON_MAGIC_BYTE_2
            || header.2 != Constants.TNS_JSON_MAGIC_BYTE_3
        {
            throw OracleError.ErrorType.unexpectedData
        }
        let version = try buffer.throwingReadInteger(as: UInt8.self)
        if version != Constants.TNS_JSON_VERSION_MAX_FNAME_255
            && version != Constants.TNS_JSON_VERSION_MAX_FNAME_65535
        {
            throw OracleError.ErrorType.osonVersionNotSupported
        }

        // if value is a scalar value, the header is much smaller
        self.flags = try buffer.throwingReadInteger(as: UInt16.self)
        self.relativeOffsets = self.flags & Constants.TNS_JSON_FLAG_REL_OFFSET_MODE != 0
        if self.flags & Constants.TNS_JSON_FLAG_IS_SCALAR != 0 {
            if self.flags & Constants.TNS_JSON_FLAG_TREE_SEG_UINT32 != 0 {
                buffer.moveReaderIndex(forwardBy: 4)
            } else {
                buffer.moveReaderIndex(forwardBy: 2)
            }
            return try decodeNode(from: &buffer)
        }

        // determine the number of field names
        let shortFieldNamesCount: Int
        if self.flags & Constants.TNS_JSON_FLAG_NUM_FNAMES_UINT32 != 0 {
            shortFieldNamesCount = try Int(buffer.throwingReadInteger(as: UInt32.self))
            self.fieldIDLength = 4
        } else if self.flags & Constants.TNS_JSON_FLAG_NUM_FNAMES_UINT16 != 0 {
            shortFieldNamesCount = try Int(buffer.throwingReadInteger(as: UInt16.self))
            self.fieldIDLength = 2
        } else {
            shortFieldNamesCount = try Int(buffer.throwingReadInteger(as: UInt8.self))
            self.fieldIDLength = 1
        }

        // determine the size of the field names segment
        let shortFieldNameOffsetsSize: Int
        let shortFieldNamesSegSize: Int
        if self.flags & Constants.TNS_JSON_FLAG_FNAMES_SEG_UINT32 != 0 {
            shortFieldNameOffsetsSize = 4
            shortFieldNamesSegSize = try Int(buffer.throwingReadInteger(as: UInt32.self))
        } else {
            shortFieldNameOffsetsSize = 2
            shortFieldNamesSegSize = try Int(buffer.throwingReadInteger(as: UInt16.self))
        }

        let longFieldNameOffsetsSize: Int
        let longFieldNamesCount: Int
        let longFieldNamesSegSize: Int
        if version == Constants.TNS_JSON_VERSION_MAX_FNAME_65535 {
            let secondaryFlags = try buffer.throwingReadInteger(as: UInt16.self)
            if secondaryFlags & Constants.TNS_JSON_FLAG_SEC_FNAMES_SEG_UINT16 != 0 {
                longFieldNameOffsetsSize = 2
            } else {
                longFieldNameOffsetsSize = 4
            }
            longFieldNamesCount = try Int(buffer.throwingReadInteger(as: UInt32.self))
            longFieldNamesSegSize = try Int(buffer.throwingReadInteger(as: UInt32.self))
        } else {
            longFieldNameOffsetsSize = 0
            longFieldNamesCount = 0
            longFieldNamesSegSize = 0
        }

        // determine the size of the tree segment - unused
        if self.flags & Constants.TNS_JSON_FLAG_TREE_SEG_UINT32 != 0 {
            buffer.moveReaderIndex(forwardBy: MemoryLayout<UInt32>.size)
        } else {
            buffer.moveReaderIndex(forwardBy: MemoryLayout<UInt16>.size)
        }

        // determine the number of "tiny" nodes - unused
        buffer.moveReaderIndex(forwardBy: MemoryLayout<UInt16>.size)

        // if there are any short names, read them now
        if shortFieldNamesCount > 0 {
            try self.getShortFieldNames(
                from: &buffer,
                fieldsCount: shortFieldNamesCount,
                offsetsSize: shortFieldNameOffsetsSize,
                segmentSize: shortFieldNamesSegSize
            )
        }

        // if there are any long names, read them now
        if longFieldNamesCount > 0 {
            try self.getLongFieldNames(
                from: &buffer,
                fieldsCount: longFieldNamesCount,
                offsetsSize: longFieldNameOffsetsSize,
                segmentSize: longFieldNamesSegSize
            )
        }

        // get tree segment
        self.treeSegPosition = buffer.readerIndex

        return try decodeNode(from: &buffer)
    }

    mutating func getShortFieldNames(
        from buffer: inout ByteBuffer,
        fieldsCount: Int,
        offsetsSize: Int,
        segmentSize: Int
    ) throws {
        // skip the hash id array (1 byte for each field)
        buffer.moveReaderIndex(forwardBy: fieldsCount)

        // skip the field name offsets array for now
        let offsetsPosition = buffer.readerIndex
        buffer.moveReaderIndex(forwardBy: fieldsCount * offsetsSize)
        let slice = try buffer.throwingReadSlice(length: segmentSize)
        let finalPosition = buffer.readerIndex

        // determine the names of the fields
        buffer.moveReaderIndex(to: offsetsPosition)
        self.fieldNames.reserveCapacity(fieldsCount)
        for _ in 0..<fieldsCount {
            let offset =
                if offsetsSize == 2 {
                    try Int(buffer.throwingReadInteger(as: UInt16.self))
                } else {
                    try Int(buffer.throwingReadInteger(as: UInt32.self))
                }

            let length = try Int(slice.throwingGetInteger(at: offset, as: UInt8.self))
            let name = try slice.throwingGetString(
                at: offset + MemoryLayout<UInt8>.size, length: length)
            self.fieldNames.append(name)
        }
        buffer.moveReaderIndex(to: finalPosition)
    }

    mutating func getLongFieldNames(
        from buffer: inout ByteBuffer,
        fieldsCount: Int,
        offsetsSize: Int,
        segmentSize: Int
    ) throws {
        // skip the hash id array (2 bytes for each field)
        buffer.moveReaderIndex(forwardBy: fieldsCount * 2)

        // skip the field name offsets array for now
        buffer.moveReaderIndex(forwardBy: fieldsCount * offsetsSize)
        var slice = try buffer.throwingReadSlice(length: segmentSize)

        // determine the names of the fields
        self.fieldNames.reserveCapacity(fieldsCount)
        for _ in 0..<fieldsCount {
            let length = try Int(slice.throwingReadInteger(as: UInt16.self))
            let name = try slice.throwingReadString(length: length)
            self.fieldNames.append(name)
        }
    }

    private mutating func decodeNode(from buffer: inout ByteBuffer) throws -> OracleJSONStorage {
        let nodeType = try buffer.throwingReadInteger(as: UInt8.self)
        if nodeType & 0x80 != 0 {
            return try decodeContainerNode(from: &buffer, ofType: nodeType)
        }

        var bytes: ByteBuffer
        switch nodeType {
        case Constants.TNS_JSON_TYPE_NULL:
            return .none
        case Constants.TNS_JSON_TYPE_TRUE:
            return .bool(true)
        case Constants.TNS_JSON_TYPE_FALSE:
            return .bool(false)

        // handle fixed length scalars
        case Constants.TNS_JSON_TYPE_DATE, Constants.TNS_JSON_TYPE_TIMESTAMP7:
            bytes = try buffer.throwingReadSlice(length: 7)
            return try .date(Date(from: &bytes, type: .date, context: .default))
        case Constants.TNS_JSON_TYPE_TIMESTAMP:
            bytes = try buffer.throwingReadSlice(length: 11)
            return try .date(Date(from: &bytes, type: .timestamp, context: .default))
        case Constants.TNS_JSON_TYPE_TIMESTAMP_TZ:
            bytes = try buffer.throwingReadSlice(length: 13)
            return try .date(Date(from: &bytes, type: .timestampTZ, context: .default))
        case Constants.TNS_JSON_TYPE_BINARY_FLOAT:
            bytes = try buffer.throwingReadSlice(length: 4)
            return try .float(
                Float(
                    from: &bytes, type: .binaryFloat, context: .default
                ))
        case Constants.TNS_JSON_TYPE_BINARY_DOUBLE:
            bytes = try buffer.throwingReadSlice(length: 8)
            return try .double(
                Double(
                    from: &bytes, type: .binaryDouble, context: .default
                ))
        case Constants.TNS_JSON_TYPE_INTERVAL_DS:
            bytes = try buffer.throwingReadSlice(length: 11)
            return try .intervalDS(
                IntervalDS(
                    from: &bytes, type: .intervalDS, context: .default
                ))
        case Constants.TNS_JSON_TYPE_INTERVAL_YM:
            throw OracleError.ErrorType.dbTypeNotSupported

        // handle scalars with lengths stored outside the node itself
        case Constants.TNS_JSON_TYPE_STRING_LENGTH_UINT8:
            let temp8 = try buffer.throwingReadInteger(as: UInt8.self)
            return try .string(buffer.throwingReadString(length: Int(temp8)))
        case Constants.TNS_JSON_TYPE_STRING_LENGTH_UINT16:
            let temp16 = try buffer.throwingReadInteger(as: UInt16.self)
            return try .string(buffer.throwingReadString(length: Int(temp16)))
        case Constants.TNS_JSON_TYPE_STRING_LENGTH_UINT32:
            let temp32 = try buffer.throwingReadInteger(as: UInt32.self)
            return try .string(buffer.throwingReadString(length: Int(temp32)))
        case Constants.TNS_JSON_TYPE_NUMBER_LENGTH_UINT8:
            let length = Int(try buffer.throwingReadInteger(as: UInt8.self))
            var slice = try buffer.throwingReadSlice(length: length)
            let value: Double = try OracleNumeric.parseFloat(from: &slice)
            return .double(value)
        case Constants.TNS_JSON_TYPE_BINARY_LENGTH_UINT16:
            let temp16 = try buffer.throwingReadInteger(as: UInt16.self)
            return .int(Int(temp16))
        case Constants.TNS_JSON_TYPE_BINARY_LENGTH_UINT32:
            let temp32 = try buffer.throwingReadInteger(as: UInt32.self)
            return .int(Int(temp32))

        case Constants.TNS_JSON_TYPE_EXTENDED:
            let nodeType = try buffer.throwingReadInteger(as: UInt8.self)
            if nodeType == Constants.TNS_JSON_TYPE_VECTOR {
                let length = try buffer.throwingReadInteger(as: UInt32.self)
                var slice = try buffer.throwingReadSlice(length: Int(length))
                let (format, elements) = try _decodeOracleVectorMetadata(from: &slice)
                switch format {
                case .int8:
                    let vector = try OracleVectorInt8._decodeActual(
                        from: &slice, elements: elements)
                    return .vectorInt8(vector)
                case .float32:
                    let vector = try OracleVectorFloat32._decodeActual(
                        from: &slice, elements: elements)
                    return .vectorFloat32(vector)
                case .float64:
                    let vector = try OracleVectorFloat64._decodeActual(
                        from: &slice, elements: elements)
                    return .vectorFloat64(vector)
                case .binary:
                    let vector = try OracleVectorBinary._decodeActual(
                        from: &slice,
                        elements: elements
                    )
                    return .vectorBinary(vector)
                }
            }

        default: break
        }


        // handle number/decimal with length stored inside the node itself
        if [0x20, 0x60].contains(nodeType & 0xf0) {
            let temp8 = nodeType & 0x0f
            bytes = try buffer.throwingReadSlice(length: Int(temp8) + 1)
            return try .double(
                OracleNumber(
                    from: &bytes, type: .number, context: .default
                ).requireDouble())
        }

        // handle integer with length stored inside the node itself
        if [0x40, 0x50].contains(nodeType & 0xf0) {
            let temp8 = nodeType & 0x0f
            bytes = try buffer.throwingReadSlice(length: Int(temp8))
            return try .double(
                OracleNumber(
                    from: &bytes, type: .number, context: .default
                ).requireDouble())
        }

        // handle string with length stored inside the node itself
        if nodeType & 0xe0 == 0 {
            if nodeType == 0 {
                return .string("")
            }
            return try .string(buffer.throwingReadString(length: Int(nodeType)))
        }

        throw OracleError.ErrorType.osonNodeTypeNotSupported
    }

    private mutating func decodeContainerNode(from buffer: inout ByteBuffer, ofType nodeType: UInt8)
        throws -> OracleJSONStorage
    {
        let isObject = nodeType & 0x40 == 0

        // determine the number of children by examining the 4th and 5th most
        // significant bits of the node type; determine the offsets in the tree
        // segment to the field ids array and the value offsets array
        let containerOffset = buffer.readerIndex - self.treeSegPosition - 1
        var (numberOfChildren, isShared) = try self.getNumberOfChildren(
            from: &buffer,
            nodeType: nodeType
        )
        var offsetPosition: Int
        var fieldIDsPosition: Int
        var value: OracleJSONStorage
        if isShared {
            value = .container([:])
            let offset = try self.getOffset(from: &buffer, nodeType: nodeType)
            offsetPosition = buffer.readerIndex
            buffer.moveReaderIndex(to: self.treeSegPosition + Int(offset))
            let temp8 = try buffer.throwingReadInteger(as: UInt8.self)
            (numberOfChildren, isShared) = try self.getNumberOfChildren(
                from: &buffer,
                nodeType: temp8
            )
            fieldIDsPosition = buffer.readerIndex
        } else if isObject {
            value = .container([:])
            fieldIDsPosition = buffer.readerIndex
            offsetPosition = buffer.readerIndex + self.fieldIDLength * Int(numberOfChildren)
        } else {
            fieldIDsPosition = 0
            value = .array(.init(repeating: .none, count: Int(numberOfChildren)))
            offsetPosition = buffer.readerIndex
        }

        // process each of the children
        for i in 0..<numberOfChildren {
            let name: String?
            if isObject {
                buffer.moveReaderIndex(to: fieldIDsPosition)
                let index =
                    if self.fieldIDLength == 1 {
                        try Int(buffer.throwingReadInteger(as: UInt8.self))
                    } else if self.fieldIDLength == 2 {
                        try Int(buffer.throwingReadInteger(as: UInt16.self))
                    } else {
                        try Int(buffer.throwingReadInteger(as: UInt32.self))
                    }
                name = self.fieldNames[index - 1]
                fieldIDsPosition = buffer.readerIndex
            } else {
                name = nil
            }
            buffer.moveReaderIndex(to: offsetPosition)
            var offset = try Int(self.getOffset(from: &buffer, nodeType: nodeType))
            if self.relativeOffsets {
                offset += containerOffset
            }
            offsetPosition = buffer.readerIndex
            buffer.moveReaderIndex(to: self.treeSegPosition + offset)
            switch value {
            case .container(var dictionary):
                guard let name else { continue }
                dictionary[name] = try self.decodeNode(from: &buffer)
                value = .none  // no CoW
                value = .container(dictionary)
            case .array(var array):
                array[Int(i)] = try self.decodeNode(from: &buffer)
                value = .none  // no CoW
                value = .array(array)
            default:
                preconditionFailure()
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
        from buffer: inout ByteBuffer,
        nodeType: UInt8
    ) throws -> (numberOfChildren: UInt32, isShared: Bool) {
        let childrenBits = nodeType & 0x18
        let isShared = childrenBits == 0x18
        let numberOfChildren: UInt32
        if childrenBits == 0 {
            let temp8 = try buffer.throwingReadInteger(as: UInt8.self)
            numberOfChildren = UInt32(temp8)
        } else if childrenBits == 0x08 {
            let temp16 = try buffer.throwingReadInteger(as: UInt16.self)
            numberOfChildren = UInt32(temp16)
        } else if childrenBits == 0x10 {
            numberOfChildren = try buffer.throwingReadInteger(as: UInt32.self)
        } else {
            numberOfChildren = 0
        }
        return (numberOfChildren, isShared)
    }

    /// Return an offset. The offset will be either a 16-bit or 32-bit value
    /// depending on the value of the 3rd significant bit of the node type.
    mutating func getOffset(from buffer: inout ByteBuffer, nodeType: UInt8) throws -> UInt32 {
        if nodeType & 0x20 != 0 {
            return try buffer.throwingReadInteger(as: UInt32.self)
        }
        return try UInt32(buffer.throwingReadInteger(as: UInt16.self))
    }
}
