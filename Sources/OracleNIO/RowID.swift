struct RowID {
    var rba: UInt32 = 0
    var partitionID: UInt16 = 0
    var blockNumber: UInt32 = 0
    var slotNumber: UInt16 = 0

    static func read(from message: inout TNSMessage) -> RowID? {
        return message.packet.readRowID()
    }

    func string() -> String? {
        if rba != 0 || partitionID != 0 || blockNumber != 0 || slotNumber != 0 {
            var buffer = [UInt8](repeating: 0, count: Constants.TNS_MAX_ROWID_LENGTH)
            var offset = 0
            offset = convertBase64(buffer: &buffer, value: Int(rba), size: 6, offset: offset)
            offset = convertBase64(buffer: &buffer, value: Int(partitionID), size: 3, offset: offset)
            offset = convertBase64(buffer: &buffer, value: Int(blockNumber), size: 6, offset: offset)
            offset = convertBase64(buffer: &buffer, value: Int(slotNumber), size: 3, offset: offset)
            return String(cString: buffer)
        }
        return nil
    }

    private func convertBase64(buffer: inout [UInt8], value: Int, size: Int, offset: Int) -> Int {
        var value = value
        for i in 0..<size {
            buffer[offset + size - i - 1] = Constants.TNS_BASE64_ALPHABET_ARRAY[value & 0x3f]
            value = value >> 6
        }
        return offset + size
    }
}
