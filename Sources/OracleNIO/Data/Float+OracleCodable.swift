import NIOCore

extension Float: OracleDecodable {
    public init<JSONDecoder: OracleJSONDecoder>(
        from buffer: inout ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext<JSONDecoder>
    ) throws {
        switch type {
        case .number, .binaryInteger:
            self = try OracleNumeric.parseFloat(from: &buffer)
        case .binaryFloat:
            self = try OracleNumeric.parseBinaryFloat(from: &buffer)
        default:
            throw OracleDecodingError.Code.typeMismatch
        }
    }
}
