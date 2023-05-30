protocol OracleDecodable {
    init(from buffer: inout ByteBuffer, type: DataType.Value) throws
}
