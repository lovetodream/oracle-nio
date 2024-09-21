import NIOCore

struct OracleJSONWriter {
    var maxFieldNameSize: Int = 255
    var fieldNames: [String: FieldName] = [:]
    var shortFieldNamesSegment: FieldNameSegment?
    var longFieldNamesSegment: FieldNameSegment?
    var fieldIDSize = 0

    mutating func encode(
        _ value: OracleJSONStorage, into buffer: inout ByteBuffer, maxFieldNameSize: Int
    ) throws {
        self.maxFieldNameSize = maxFieldNameSize
        var flags = try self.determineFlags(for: value)

        var treeSegment = TreeSegment(buffer: ByteBuffer(), writer: self)
        try treeSegment.encodeNode(value)
        if treeSegment.buffer.writerIndex > 65535 {
            flags |= Constants.TNS_JSON_FLAG_TREE_SEG_UINT32
        }

        // write initial header
        buffer.writeInteger(Constants.TNS_JSON_MAGIC_BYTE_1)
        buffer.writeInteger(Constants.TNS_JSON_MAGIC_BYTE_2)
        buffer.writeInteger(Constants.TNS_JSON_MAGIC_BYTE_3)
        if longFieldNamesSegment != nil {
            buffer.writeInteger(Constants.TNS_JSON_VERSION_MAX_FNAME_65535)
        } else {
            buffer.writeInteger(Constants.TNS_JSON_VERSION_MAX_FNAME_255)
        }
        buffer.writeInteger(flags)

        // write extended header (when value is not scalar)
        if let shortFieldNamesSegment {
            writeExtendedHeader(into: &buffer, shortFieldNamesSegment: shortFieldNamesSegment)
        }

        // write size of tree segment
        if treeSegment.buffer.writerIndex < 65535 {
            buffer.writeInteger(UInt16(treeSegment.buffer.writerIndex))
        } else {
            buffer.writeInteger(UInt32(treeSegment.buffer.writerIndex))
        }

        // write remainder of header and any data (when value is not scalar)
        if let shortFieldNamesSegment {

            // write number of "tiny" nodes (always zero)
            buffer.writeInteger(0, as: UInt16.self)

            // write field name segment
            writeFieldNameSegment(shortFieldNamesSegment, into: &buffer)
            if let longFieldNamesSegment {
                writeFieldNameSegment(longFieldNamesSegment, into: &buffer)
            }

        }

        // write tree segment data
        buffer.writeImmutableBuffer(treeSegment.buffer)
    }

    private func writeFieldNameSegment(_ segment: FieldNameSegment, into buffer: inout ByteBuffer) {
        // write array of hash ids
        for name in segment.names {
            if name.nameBytes.count <= 255 {
                buffer.writeInteger(UInt8(name.hashID & 0xff))
            } else {
                buffer.writeInteger(UInt16(name.hashID & 0xffff))
            }
        }

        // write array of field name offsets for the short field names
        for name in segment.names {
            if segment.buffer.writerIndex < 65535 {
                buffer.writeInteger(UInt16(name.offset))
            } else {
                buffer.writeInteger(UInt32(name.offset))
            }
        }

        // write field names
        if segment.buffer.writerIndex > 0 {
            buffer.writeImmutableBuffer(segment.buffer)
        }
    }

    private mutating func writeExtendedHeader(
        into buffer: inout ByteBuffer, shortFieldNamesSegment: FieldNameSegment
    ) {
        var secondaryFlags: UInt16 = 0

        // write number of short field names
        if fieldIDSize == 1 {
            buffer.writeInteger(UInt8(shortFieldNamesSegment.names.count))
        } else if fieldIDSize == 2 {
            buffer.writeInteger(UInt16(shortFieldNamesSegment.names.count))
        } else {
            buffer.writeInteger(UInt32(shortFieldNamesSegment.names.count))
        }

        // write size of short field names segment
        if shortFieldNamesSegment.buffer.writerIndex < 65535 {
            buffer.writeInteger(UInt16(shortFieldNamesSegment.buffer.writerIndex))
        } else {
            buffer.writeInteger(UInt32(shortFieldNamesSegment.buffer.writerIndex))
        }

        // write fields for long field names segment, if applicable
        if let longFieldNamesSegment {
            if longFieldNamesSegment.buffer.writerIndex < 65535 {
                secondaryFlags = Constants.TNS_JSON_FLAG_SEC_FNAMES_SEG_UINT16
            }
            buffer.writeInteger(secondaryFlags)
            buffer.writeInteger(UInt32(longFieldNamesSegment.names.count))
            buffer.writeInteger(UInt32(longFieldNamesSegment.buffer.writerIndex))
        }
    }

    private mutating func determineFlags(for value: OracleJSONStorage) throws -> UInt16 {
        // if value is a single scalar, nothing more needs to be done
        var flags = Constants.TNS_JSON_FLAG_INLINE_LEAF
        switch value {
        case .array, .container:
            break
        default:
            flags |= Constants.TNS_JSON_FLAG_IS_SCALAR
            return flags
        }

        // examine all values recursively to determine the unique set of field
        // names and whether they need to be added to the long field names
        // segment (> 255 bytes) or short field names segment (<= 255 bytes)
        self.fieldNames = [:]
        self.shortFieldNamesSegment = FieldNameSegment(buffer: ByteBuffer(), names: [])
        try self.examineNode(value)

        // perform processing of field names segments and determine the total
        // number of unique field names in the value
        if shortFieldNamesSegment != nil {
            shortFieldNamesSegment!.processNames(fieldIDOffset: 0)
        }
        if longFieldNamesSegment != nil {
            longFieldNamesSegment!.processNames(
                fieldIDOffset: shortFieldNamesSegment?.names.count ?? 0)
        }


        // determine remaining flags and field id size
        let fieldNamesCount =
            (shortFieldNamesSegment?.names.count ?? 0) + (longFieldNamesSegment?.names.count ?? 0)
        flags |= Constants.TNS_JSON_FLAG_HASH_ID_UINT8 | Constants.TNS_JSON_FLAG_TINY_NODES_STAT
        if fieldNamesCount > 65535 {
            flags |= Constants.TNS_JSON_FLAG_NUM_FNAMES_UINT32
            self.fieldIDSize = 4
        } else if fieldNamesCount > 255 {
            flags |= Constants.TNS_JSON_FLAG_NUM_FNAMES_UINT16
            self.fieldIDSize = 2
        } else {
            self.fieldIDSize = 1
        }
        if let shortFieldNamesSegment, shortFieldNamesSegment.buffer.writerIndex > 65535 {
            flags |= Constants.TNS_JSON_FLAG_FNAMES_SEG_UINT32
        }
        return flags
    }

    private mutating func examineNode(_ node: OracleJSONStorage) throws {
        switch node {
        case .array(let array):
            for element in array {
                try self.examineNode(element)
            }
        case .container(let dictionary):
            for (key, value) in dictionary {
                if !fieldNames.keys.contains(key) {
                    try self.addFieldName(key)
                }
                try self.examineNode(value)
            }
        default:
            return
        }
    }

    private mutating func addFieldName(_ name: String) throws {
        var fieldName = try FieldName(name: name, maxFieldNameSize: maxFieldNameSize)
        if fieldName.nameBytes.count <= 255 {
            shortFieldNamesSegment!.addName(&fieldName)
            fieldNames[name] = fieldName
        } else {
            if longFieldNamesSegment == nil {
                longFieldNamesSegment = .init()
            }
            longFieldNamesSegment!.addName(&fieldName)
            fieldNames[name] = fieldName
        }
    }
}

// has to be reference type for now
// because it is passed around various places
final class FieldName {
    let hashID: Int
    let nameBytes: [UInt8]
    let name: String
    var offset = 0
    var fieldID = 0

    /// Calculates the hash id to use for the field name.
    ///
    /// This is based on Bernstein's hash function.
    static func calculateHashID(for name: [UInt8]) -> Int {
        var hashID = 0x811C_9DC5
        for c in name {
            hashID = (hashID ^ Int(c)) &* 16_777_619
        }
        return hashID
    }

    init(name: String, maxFieldNameSize: Int) throws {
        self.name = name
        self.nameBytes = Array(name.utf8)
        if self.nameBytes.count > maxFieldNameSize {
            throw EncodingError.invalidValue(
                name,
                EncodingError.Context(
                    codingPath: [],
                    debugDescription: "Field name too long"
                )
            )
        }
        self.hashID = Self.calculateHashID(for: nameBytes)
    }

    /// Returns the sort key to use when sorting field names.
    func sortKey() -> (Int, Int, [UInt8]) {
        return (hashID & 0xFF, nameBytes.count, nameBytes)
    }
}

struct FieldNameSegment {
    var buffer = ByteBuffer()
    var names: [FieldName] = []

    mutating func addName(_ name: inout FieldName) {
        name.offset = buffer.writerIndex
        if name.nameBytes.count <= 255 {
            buffer.writeInteger(UInt8(name.nameBytes.count))
        } else {
            buffer.writeInteger(UInt16(name.nameBytes.count))
        }
        buffer.writeBytes(name.nameBytes)
        names.append(name)
    }

    mutating func processNames(fieldIDOffset: Int) {
        names.sort { (lhs: FieldName, rhs: FieldName) in
            let lhs = lhs.sortKey()
            let rhs = rhs.sortKey()
            if lhs.0 < rhs.0 {
                return true
            }
            if lhs.0 == rhs.0 && lhs.1 < rhs.1 {
                return true
            }
            if lhs.0 == rhs.0 && lhs.1 == rhs.1 {
                for (l, r) in zip(lhs.2, rhs.2) {
                    if l < r {
                        return true
                    }
                    if l > r {
                        return false
                    }
                }
            }
            return false
        }
        for i in names.indices {
            names[i].fieldID = fieldIDOffset + i + 1
        }
    }
}

struct TreeSegment {
    var buffer: ByteBuffer
    var writer: OracleJSONWriter

    mutating func encodeNode(_ value: OracleJSONStorage) throws {
        switch value {
        case .none:
            buffer.writeInteger(Constants.TNS_JSON_TYPE_NULL)

        case .bool(let value):
            if value {
                buffer.writeInteger(Constants.TNS_JSON_TYPE_TRUE)
            } else {
                buffer.writeInteger(Constants.TNS_JSON_TYPE_FALSE)
            }

        // TODO: revisit numeric conversions
        case .int(let value):
            buffer.writeInteger(Constants.TNS_JSON_TYPE_NUMBER_LENGTH_UINT8)
            try buffer.writeLengthPrefixed(as: UInt8.self) { buffer in
                OracleNumeric.encodeNumeric(value, into: &buffer)
            }
        case .float(let value):
            buffer.writeInteger(Constants.TNS_JSON_TYPE_NUMBER_LENGTH_UINT8)
            try buffer.writeLengthPrefixed(as: UInt8.self) { buffer in
                OracleNumeric.encodeNumeric(value, into: &buffer)
            }
        case .double(let value):
            buffer.writeInteger(Constants.TNS_JSON_TYPE_NUMBER_LENGTH_UINT8)
            try buffer.writeLengthPrefixed(as: UInt8.self) { buffer in
                OracleNumeric.encodeNumeric(value, into: &buffer)
            }

        case .date(let value):
            buffer.writeInteger(Constants.TNS_JSON_TYPE_TIMESTAMP_TZ)
            value.encode(into: &buffer, context: .default)

        case .intervalDS(let value):
            buffer.writeInteger(Constants.TNS_JSON_TYPE_INTERVAL_DS)
            value.encode(into: &buffer, context: .default)

        case .string(let value):
            let bytes = Array(value.utf8)
            switch bytes.count {
            case ..<256:
                buffer.writeInteger(Constants.TNS_JSON_TYPE_STRING_LENGTH_UINT8)
                try buffer.writeLengthPrefixed(as: UInt8.self) { $0.writeBytes(bytes) }
            case ..<65536:
                buffer.writeInteger(Constants.TNS_JSON_TYPE_STRING_LENGTH_UINT16)
                try buffer.writeLengthPrefixed(as: UInt16.self) { $0.writeBytes(bytes) }
            default:
                buffer.writeInteger(Constants.TNS_JSON_TYPE_STRING_LENGTH_UINT32)
                try buffer.writeLengthPrefixed(as: UInt32.self) { $0.writeBytes(bytes) }
            }

        case .vectorInt8(let vector):
            buffer.writeInteger(Constants.TNS_JSON_TYPE_EXTENDED)
            buffer.writeInteger(Constants.TNS_JSON_TYPE_VECTOR)
            vector.encodeForJSON(into: &buffer)
        case .vectorFloat32(let vector):
            buffer.writeInteger(Constants.TNS_JSON_TYPE_EXTENDED)
            buffer.writeInteger(Constants.TNS_JSON_TYPE_VECTOR)
            vector.encodeForJSON(into: &buffer)
        case .vectorFloat64(let vector):
            buffer.writeInteger(Constants.TNS_JSON_TYPE_EXTENDED)
            buffer.writeInteger(Constants.TNS_JSON_TYPE_VECTOR)
            vector.encodeForJSON(into: &buffer)

        case .array(let array):
            try encodeArray(array)

        case .container(let dictionary):
            try encodeObject(dictionary)
        }
    }

    mutating func encodeContainer(nodeType: UInt8, count: Int) {
        var nodeType = nodeType
        nodeType |= 0x20  // use UInt32 for offsets
        if count > 65535 {
            nodeType |= 0x10  // count is UInt32
        } else if count > 255 {
            nodeType |= 0x08  // count is UInt16
        }
        buffer.writeInteger(nodeType)
        if count < 256 {
            buffer.writeInteger(UInt8(count))
        } else if count < 65536 {
            buffer.writeInteger(UInt16(count))
        } else {
            buffer.writeInteger(UInt32(count))
        }
    }

    mutating func encodeArray(_ array: [OracleJSONStorage]) throws {
        encodeContainer(nodeType: Constants.TNS_JSON_TYPE_ARRAY, count: array.count)
        var offset = buffer.writerIndex
        buffer.writeRepeatingByte(0, count: array.count * MemoryLayout<UInt32>.size)
        for element in array {
            buffer.setInteger(UInt32(buffer.writerIndex), at: offset, endianness: .big)
            offset += MemoryLayout<UInt32>.size
            try encodeNode(element)
        }
    }

    mutating func encodeObject(_ dictionary: [String: OracleJSONStorage]) throws {
        encodeContainer(nodeType: Constants.TNS_JSON_TYPE_OBJECT, count: dictionary.count)
        var fieldIDOffset = buffer.writerIndex
        var valueOffset = buffer.writerIndex + dictionary.count * writer.fieldIDSize
        let finalOffset = valueOffset + dictionary.count * MemoryLayout<UInt32>.size
        buffer.writeRepeatingByte(0, count: finalOffset - buffer.writerIndex)
        for (key, value) in dictionary {
            guard let fieldName = writer.fieldNames[key] else {
                throw EncodingError.invalidValue(
                    key,
                    EncodingError.Context(
                        codingPath: [], debugDescription: "Unknown field name: \(key)"))
            }
            if writer.fieldIDSize == 1 {
                buffer.setInteger(UInt8(fieldName.fieldID), at: fieldIDOffset, endianness: .big)
            } else if writer.fieldIDSize == 2 {
                buffer.setInteger(UInt16(fieldName.fieldID), at: fieldIDOffset, endianness: .big)
            } else {
                buffer.setInteger(UInt32(fieldName.fieldID), at: fieldIDOffset, endianness: .big)
            }
            buffer.setInteger(UInt32(buffer.writerIndex), at: valueOffset, endianness: .big)
            fieldIDOffset += writer.fieldIDSize
            valueOffset += MemoryLayout<UInt32>.size
            try self.encodeNode(value)
        }
    }
}
