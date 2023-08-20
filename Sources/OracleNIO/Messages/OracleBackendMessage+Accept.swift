import NIOCore

extension OracleBackendMessage {
    struct Accept: PayloadDecodable, Hashable {
        var newCapabilities: Capabilities

        static func decode(
            from buffer: inout ByteBuffer,
            capabilities: Capabilities
        ) throws -> OracleBackendMessage.Accept {
            let protocolVersion =
                try buffer.throwingReadInteger(as: UInt16.self)
            let protocolOptions =
                try buffer.throwingReadInteger(as: UInt16.self)

            let cap = capabilities.adjustedForProtocol(
                version: protocolVersion,
                options: protocolOptions
            )

            if cap.protocolVersion < Constants.TNS_VERSION_MIN_ACCEPTED {
                throw OracleError.ErrorType.serverVersionNotSupported
            }

            if
                cap.supportsOOB && cap.protocolVersion >=
                Constants.TNS_VERSION_MIN_OOB_CHECK
            {
                // TODO: Perform OOB Check
            }


            return .init(newCapabilities: cap)
        }
    }
}
