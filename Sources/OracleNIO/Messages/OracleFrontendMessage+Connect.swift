extension OracleFrontendMessage {
    struct Connect: PayloadEncodable, Hashable {

        let connectString: String

        var packetType: PacketType { .connect }

        func encode(into buffer: inout NIOCore.ByteBuffer,
                    capabilities: Capabilities) {
            var serviceOptions = Constants.TNS_GSO_DONT_CARE
            let connectFlags1: UInt32 = 0
            var connectFlags2: UInt32 = 0
            let nsiFlags: UInt8 = Constants.TNS_NSI_SUPPORT_SECURITY_RENEG
                | Constants.TNS_NSI_DISABLE_NA
            if capabilities.supportsOOB {
                serviceOptions |= Constants.TNS_GSO_CAN_RECV_ATTENTION
                connectFlags2 |= Constants.TNS_CHECK_OOB
            }
            let connectStringByteLength = connectString
                .lengthOfBytes(using: .utf8)

            buffer.writeMultipleIntegers(
                Constants.TNS_VERSION_DESIRED,
                Constants.TNS_VERSION_MINIMUM,
                serviceOptions,
                Constants.TNS_SDU,
                Constants.TNS_TDU,
                Constants.TNS_PROTOCOL_CHARACTERISTICS,
                UInt16(0), // line turnaround
                UInt16(1), // value of 1
                UInt16(connectStringByteLength)
            )
            buffer.writeMultipleIntegers(
                UInt16(74), // offset to connect data
                UInt32(0), // max receivable data
                nsiFlags,
                nsiFlags,
                UInt64(0), // obsolete
                UInt64(0), // obsolete
                UInt64(0), // obsolete
                UInt32(Constants.TNS_SDU), // SDU (large)
                UInt32(Constants.TNS_TDU), // SDU (large)
                connectFlags1,
                connectFlags2
            )
            if connectStringByteLength > Constants.TNS_MAX_CONNECT_DATA {
                // TODO: end request and start new one
                fatalError()
            }
            buffer.writeString(connectString)

        }
    }
}
