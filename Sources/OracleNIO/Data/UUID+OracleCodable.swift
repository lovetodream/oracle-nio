import struct Foundation.UUID
import NIOCore

extension UUID: OracleDecodable {
    public init<JSONDecoder: OracleJSONDecoder>(
        from buffer: inout ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext<JSONDecoder>
    ) throws {
        switch type {
        case .raw, .longRAW:
            guard let uuid = buffer.readUUIDBytes() else {
                throw OracleDecodingError.Code.failure
            }
            self = uuid
        case .varchar, .long:
            guard buffer.readableBytes == 36 else {
               throw OracleDecodingError.Code.failure
           }

           guard let uuid = buffer.readString(length: 36).flatMap({ UUID(uuidString: $0) }) else {
               throw OracleDecodingError.Code.failure
           }
           self = uuid
        default:
            throw OracleDecodingError.Code.typeMismatch
        }
    }
}
