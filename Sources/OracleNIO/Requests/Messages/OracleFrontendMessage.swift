import NIOCore

/// A wire message that is created by a Oracle client to be consumed by a Oracle server.
enum OracleFrontendMessage: Equatable {
    typealias PayloadEncodable = OracleMessagePayloadEncodable

    case connect(Connect)
    case `protocol`(`Protocol`)
    case dataTypes(DataTypes)

    /// Equivalent to ``MessageType``.
    enum ID: UInt8, Equatable {

        case `protocol`
        case dataTypes
        case function

        init?(rawValue: UInt8) {
            switch rawValue {
            case 1:
                self = .protocol
            case 2:
                self = .dataTypes
            case 3:
                self = .function
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
            case .function:
                return 3
            }
        }
    }
}

extension OracleFrontendMessage {
    var id: ID {
        switch self {
        case .protocol:
            return .protocol
        case .connect:
            return .function
        case .dataTypes:
            return .dataTypes
        }
    }
}

protocol OracleMessagePayloadEncodable {
    var packetType: PacketType { get }

    func encode(into buffer: inout ByteBuffer, capabilities: Capabilities)
}
