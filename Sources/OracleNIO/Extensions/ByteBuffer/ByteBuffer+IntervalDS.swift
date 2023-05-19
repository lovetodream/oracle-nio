import NIOCore

extension ByteBuffer {
    mutating func readIntervalDS() -> Double? {
        guard let (bytes, _) = _readRawBytesAndLength(), let bytes else {
            return nil
        }
        return self.parseIntervalDS(bytes: bytes)
    }

    func parseIntervalDS(bytes: [UInt8]) -> Double {
        let durationMid = Constants.TNS_DURATION_MID
        let durationOffset = Constants.TNS_DURATION_OFFSET
        var buffer = ByteBuffer(bytes: bytes)
        let days = (buffer.readInteger(endianness: .big, as: UInt32.self) ?? 0) - durationMid
        buffer.moveReaderIndex(to: 7)
        let fractionalSeconds = (buffer.readInteger(endianness: .big, as: UInt32.self) ?? 0) - durationMid
        let hours = bytes[4] - durationOffset
        let minutes = bytes[5] - durationOffset
        let seconds = bytes[6] - durationOffset
        // seconds
        let timeInterval =
            (Double(days) * 24 * 60 * 60) +
            (Double(hours) * 60 * 60) +
            (Double(minutes) * 60) +
            Double(seconds) +
            (Double(fractionalSeconds) / 1000)
        return timeInterval
    }

    mutating func writeIntervalDS(_ value: Double, writeLength: Bool = true) { // seconds
        let days, seconds, fractionalSeconds: Int32
        days = Int32((value / 24 / 60 / 60).rounded(.down))
        seconds = Int32(value.rounded(.down))
        fractionalSeconds = Int32((value.truncatingRemainder(dividingBy: 1) * 1000).rounded())
        var buffer = ByteBuffer()
        buffer.writeInteger(UInt32(days) + Constants.TNS_DURATION_MID, endianness: .big, as: UInt32.self)
        buffer.writeInteger(UInt8(seconds / 3600) + Constants.TNS_DURATION_OFFSET)
        buffer.writeInteger(UInt8(seconds / 60) + Constants.TNS_DURATION_OFFSET)
        buffer.writeInteger(UInt8(seconds % 60) + Constants.TNS_DURATION_OFFSET)
        buffer.writeInteger(UInt32(fractionalSeconds) + Constants.TNS_DURATION_MID, endianness: .big, as: UInt32.self)
        if writeLength {
            self.writeInteger(UInt8(buffer.readableBytes))
        }
        self.writeBuffer(&buffer)
    }
}
