import NIOCore

extension ByteBuffer {
    var oracleColumnIsEmpty: Bool {
        self.readableBytes == 1 &&
        [0, Constants.TNS_NULL_LENGTH_INDICATOR].contains(self.getInteger(at: self.readerIndex, as: UInt8.self))
    }
}
