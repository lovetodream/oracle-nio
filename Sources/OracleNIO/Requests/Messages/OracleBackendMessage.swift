import NIOCore

/// A protocol to implement for all associated values in the ``OracleBackendMessage`` enum.
protocol OracleMessagePayloadDecodable {
    /// Decodes the associated value for a ``OracleBackendMessage`` from the given ``ByteBuffer``.
    ///
    /// When the decoding is done all bytes in the given ``ByteBuffer`` must be consumed.
    /// ``ByteBuffer.readableBytes`` must be `0`. In case of an error a ``PartialDecodingError``
    /// must be thrown.
    ///
    /// - Parameter buffer: The ``ByteBuffer`` to read the message from. When done the ``ByteBuffer``
    ///                     must be fully consumed.
    static func decode(from buffer: inout ByteBuffer, capabilities: Capabilities) throws -> Self
}

/// A wire message that is created by a Oracle server to be consumed by the Oracle client.
enum OracleBackendMessage {
    typealias PayloadDecodable = OracleMessagePayloadDecodable

    case rowDescription(RowDescription)
}

extension OracleBackendMessage {
    enum ID: RawRepresentable, Equatable {
        typealias RawValue =  UInt8

        /// Equivalent to ``MessageType.describeInfo``.
        case rowDescription

        init?(rawValue: UInt8) {
            switch rawValue {
            case 16:
                self = .rowDescription
            default:
                return nil
            }
        }

        var rawValue: UInt8 {
            switch self {
            case .rowDescription:
                return 16
            }
        }
    }
}

extension OracleBackendMessage {
    static func decode(from buffer: inout ByteBuffer, for messageID: ID, capabilities: Capabilities) throws -> OracleBackendMessage {
        switch messageID {
        case .rowDescription:
            return try .rowDescription(.decode(from: &buffer, capabilities: capabilities))
        }
    }
}

extension OracleBackendMessage: CustomDebugStringConvertible {
    var debugDescription: String {
        switch self {
        case .rowDescription(let rowDescription):
            return ".rowDescription(\(String(reflecting: rowDescription)))"
        }
    }
}
