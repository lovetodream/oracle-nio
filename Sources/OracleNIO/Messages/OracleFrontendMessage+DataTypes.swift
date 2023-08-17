import NIOCore

extension OracleFrontendMessage {
    struct DataTypes: PayloadEncodable, Hashable {
        var packetType: PacketType { .data }

        func encode(
            into buffer: inout ByteBuffer, capabilities: Capabilities
        ) {
            buffer.writeInteger(MessageType.dataTypes.rawValue, as: UInt8.self)
            buffer.writeInteger(Constants.TNS_CHARSET_UTF8, endianness: .little)
            buffer.writeInteger(Constants.TNS_CHARSET_UTF8, endianness: .little)
            buffer.writeUB4(UInt32(capabilities.compileCapabilities.count))
            buffer.writeBytes(capabilities.compileCapabilities)
            buffer.writeInteger(UInt8(capabilities.runtimeCapabilities.count))
            buffer.writeBytes(capabilities.runtimeCapabilities)

            var i = 0
            while true {
                let dataType = DataType.all[i]
                if dataType.dataType == .undefined { break }
                i += 1

                buffer.writeInteger(dataType.dataType.rawValue)
                buffer.writeInteger(dataType.convDataType.rawValue)
                buffer.writeInteger(dataType.representation.rawValue)
                buffer.writeInteger(UInt16(0))
            }

            buffer.writeInteger(UInt16(0))
        }
    }
}
