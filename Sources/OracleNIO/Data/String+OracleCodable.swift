import NIOCore

extension String: OracleDecodable {
    init(from buffer: inout ByteBuffer, type: DataType.Value) throws {
        switch type {
        case .varchar, .char, .long:
            self = buffer.readString(length: buffer.readableBytes)!
        default:
            throw OracleDecodingError.Code.typeMismatch
        }
    }
}
