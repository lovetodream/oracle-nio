import NIOCore

extension ByteBuffer {
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
}
