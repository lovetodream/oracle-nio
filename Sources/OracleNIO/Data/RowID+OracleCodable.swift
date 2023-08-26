public struct RowID: CustomStringConvertible, Sendable, Equatable, Hashable {
    public var rba: UInt32 = 0
    public var partitionID: UInt16 = 0
    public var blockNumber: UInt32 = 0
    public var slotNumber: UInt16 = 0

    public init(
        rba: UInt32 = 0,
        partitionID: UInt16 = 0,
        blockNumber: UInt32 = 0,
        slotNumber: UInt16 = 0
    ) {
        self.rba = rba
        self.partitionID = partitionID
        self.blockNumber = blockNumber
        self.slotNumber = slotNumber
    }


    public var description: String {
        if rba != 0 || partitionID != 0 || blockNumber != 0 || slotNumber != 0 {
            var buffer = [UInt8](
                repeating: 0, count: Constants.TNS_MAX_ROWID_LENGTH
            )
            var offset = 0
            offset = convertBase64(
                buffer: &buffer,
                value: Int(rba),
                size: 6,
                offset: offset
            )
            offset = convertBase64(
                buffer: &buffer,
                value: Int(partitionID),
                size: 3,
                offset: offset
            )
            offset = convertBase64(
                buffer: &buffer, 
                value: Int(blockNumber),
                size: 6,
                offset: offset
            )
            offset = convertBase64(
                buffer: &buffer, 
                value: Int(slotNumber),
                size: 3,
                offset: offset
            )
            return String(cString: buffer)
        }
        return "<empty>"
    }

    private func convertBase64(
        buffer: inout [UInt8],
        value: Int,
        size: Int,
        offset: Int
    ) -> Int {
        var value = value
        for i in 0..<size {
            buffer[offset + size - i - 1] = 
                Constants.TNS_BASE64_ALPHABET_ARRAY[value & 0x3f]
            value = value >> 6
        }
        return offset + size
    }
}

extension RowID: OracleDecodable {
    public init<JSONDecoder: OracleJSONDecoder>(
        from buffer: inout ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext<JSONDecoder>
    ) throws {
        switch type {
        case .rowID:
            let rba = buffer.readUB4()
            let partitionID = buffer.readUB2()
            buffer.skipUB1()
            let blockNumber = buffer.readUB4()
            let slotNumber = buffer.readUB2()
            self = RowID(
                rba: rba ?? 0,
                partitionID: partitionID ?? 0,
                blockNumber: blockNumber ?? 0,
                slotNumber: slotNumber ?? 0
            )
        default:
            throw OracleDecodingError.Code.typeMismatch
        }
    }
    
    internal init(from buffer: inout ByteBuffer) {
        try! self.init(from: &buffer, type: .rowID, context: .default)
    }
}
