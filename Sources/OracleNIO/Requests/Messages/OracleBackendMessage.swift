import NIOCore

/// A protocol to implement for all associated values in the ``OracleBackendMessage`` enum.
protocol OracleMessagePayloadDecodable {
    /// Decodes the associated value for a ``OracleBackendMessage`` from the given
    /// `ByteBuffer`.
    ///
    /// When the decoding is done all bytes in the given ``ByteBuffer`` must be consumed.
    /// ``ByteBuffer.readableBytes`` must be `0`. In case of an error a
    /// ``PartialDecodingError`` must be thrown.
    ///
    /// - Parameter buffer: The ``ByteBuffer`` to read the message from. When done the
    ///                     `ByteBuffer` must be fully consumed.
    static func decode(
        from buffer: inout ByteBuffer,
        capabilities: Capabilities
    ) throws -> Self
}

/// A wire message that is created by a Oracle server to be consumed by the Oracle client.
enum OracleBackendMessage {
    typealias PayloadDecodable = OracleMessagePayloadDecodable

    case accept(Accept)
    case dataTypes
    case marker
    case parameter(Parameter)
    case `protocol`(`Protocol`)
    case resend
    case rowDescription(RowDescription)
    case status
}

extension OracleBackendMessage {
    /// Equivalent to ``PacketType``.
    enum ID: RawRepresentable, Equatable {
        typealias RawValue = UInt8

        case accept
        case data
        case resend
        case marker

        init?(rawValue: UInt8) {
            switch rawValue {
            case 2:
                self = .accept
            case 6:
                self = .data
            case 11:
                self = .resend
            case 12:
                self = .marker
            default:
                return nil
            }
        }

        var rawValue: UInt8 {
            switch self {
            case .accept:
                return 2
            case .data:
                return 6
            case .resend:
                return 11
            case .marker:
                return 12
            }
        }
    }

    /// Equivalent to ``MessageType``.
    enum MessageID: RawRepresentable, Equatable {
        typealias RawValue =  UInt8

        case `protocol`
        case dataTypes
        case parameter
        case status
        case rowDescription

        init?(rawValue: UInt8) {
            switch rawValue {
            case 1:
                self = .protocol
            case 2:
                self = .dataTypes
            case 8:
                self = .parameter
            case 9:
                self = .status
            case 16:
                self = .rowDescription
            default:
                return nil
            }
        }

        var rawValue: UInt8 {
            switch self {
            case .protocol:
                return 1
            case .dataTypes:
                return 2
            case .parameter:
                return 8
            case .status:
                return 9
            case .rowDescription:
                return 16
            }
        }
    }
}

extension OracleBackendMessage {
    static func decode(
        from buffer: inout ByteBuffer,
        of packetID: ID,
        capabilities: Capabilities
    ) throws -> OracleBackendMessage {
        switch packetID {
        case .resend:
            return .resend
        case .accept:
            return try .accept(
                .decode(from: &buffer, capabilities: capabilities)
            )
        case .marker:
            return .marker
        case .data:
            buffer.moveReaderIndex(forwardBy: 2) // skip data flags
            let messageIDByte = try buffer.throwingReadInteger(as: UInt8.self)
            let messageID = MessageID(rawValue: messageIDByte)
            switch messageID {
            case .dataTypes:
                return .dataTypes
            case .protocol:
                return try .protocol(
                    .decode(from: &buffer, capabilities: capabilities)
                )
            case .parameter:
                return try .parameter(
                    .decode(from: &buffer, capabilities: capabilities)
                )
            case .status:
                return .status
            case .rowDescription:
                return try .rowDescription(
                    .decode(from: &buffer, capabilities: capabilities)
                )
            case nil:
                fatalError("not implemented")
            }
        }
    }
}

extension OracleBackendMessage: CustomDebugStringConvertible {
    var debugDescription: String {
        switch self {
        case .accept(let accept):
            return ".accept(\(String(reflecting: accept)))"
        case .dataTypes:
            return ".dataTypes"
        case .marker:
            return ".marker"
        case .parameter(let parameter):
            return ".parameter(\(String(reflecting: parameter))"
        case .protocol(let `protocol`):
            return ".protocol(\(String(reflecting: `protocol`)))"
        case .resend:
            return ".resend"
        case .status:
            return ".status"
        case .rowDescription(let rowDescription):
            return ".rowDescription(\(String(reflecting: rowDescription)))"
        }
    }
}
