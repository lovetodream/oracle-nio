extension TNSMessage {
    mutating func skipChunk() {
        guard let length = packet.readInteger(as: UInt8.self) else { return }
        if length != Constants.TNS_LONG_LENGTH_INDICATOR {
            packet.moveReaderIndex(forwardByBytes: Int(length))
        } else {
            while true {
                let numberOfBytes = packet.readInteger(as: UInt32.self) ?? 0
                if numberOfBytes == 0 {
                    break
                }
                packet.moveReaderIndex(forwardByBytes: Int(numberOfBytes))
            }
        }
    }
}
