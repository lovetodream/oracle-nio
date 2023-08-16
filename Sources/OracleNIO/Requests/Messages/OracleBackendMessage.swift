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
    case error(BackendError)
    case marker
    case parameter(Parameter)
    case `protocol`(`Protocol`)
    case queryParameter(QueryParameter)
    case resend
    case rowHeader(RowHeader)
    case rowData(RowData)
    case describeInfo(DescribeInfo)
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
        case error
        case rowHeader
        case rowData
        case parameter
        case status
        case describeInfo

        init?(rawValue: UInt8) {
            switch rawValue {
            case 1:
                self = .protocol
            case 2:
                self = .dataTypes
            case 4:
                self = .error
            case 6:
                self = .rowHeader
            case 7:
                self = .rowData
            case 8:
                self = .parameter
            case 9:
                self = .status
            case 16:
                self = .describeInfo
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
            case .error:
                return 4
            case .rowHeader:
                return 6
            case .rowData:
                return 7
            case .parameter:
                return 8
            case .status:
                return 9
            case .describeInfo:
                return 16
            }
        }
    }
}

extension OracleBackendMessage {
    static func decode(
        from buffer: inout ByteBuffer,
        of packetID: ID,
        capabilities: Capabilities,
        skipDataFlags: Bool = true,
        queryOptions: QueryOptions? = nil
    ) throws -> [OracleBackendMessage] {
        var messages: [OracleBackendMessage] = []
        switch packetID {
        case .resend:
            messages.append(.resend)
        case .accept:
            messages.append(try .accept(
                .decode(from: &buffer, capabilities: capabilities)
            ))
        case .marker:
            messages.append(.marker)
        case .data:
            if skipDataFlags {
                buffer.moveReaderIndex(forwardBy: 2) // skip data flags
            }
            readLoop: while buffer.readableBytes > 0 {
                let messageIDByte = try buffer.throwingReadInteger(as: UInt8.self)
                let messageID = MessageID(rawValue: messageIDByte)
                switch messageID {
                case .dataTypes:
                    messages.append(.dataTypes)
                    break readLoop
                case .protocol:
                    messages.append(try .protocol(
                        .decode(from: &buffer, capabilities: capabilities)
                    ))
                    break readLoop
                case .error:
                    messages.append(try .error(
                        .decode(from: &buffer, capabilities: capabilities)
                    ))
                case .parameter:
                    if let queryOptions {
                        messages.append(try .queryParameter(
                            .decode(
                                from: &buffer,
                                capabilities: capabilities,
                                options: queryOptions
                            )
                        ))
                    } else {
                        messages.append(try .parameter(
                            .decode(from: &buffer, capabilities: capabilities)
                        ))
                        break readLoop
                    }
                case .status:
                    messages.append(.status)
                    break readLoop
                case .describeInfo:
                    messages.append(try .describeInfo(
                        .decode(from: &buffer, capabilities: capabilities)
                    ))
                case .rowHeader:
                    messages.append(try .rowHeader(
                        .decode(from: &buffer, capabilities: capabilities)
                    ))
                case .rowData:
                    messages.append(try .rowData(
                        .decode(from: &buffer, capabilities: capabilities)
                    ))
                case nil:
                    fatalError("not implemented")
                }
            }
        }
        return messages
    }
}

extension OracleBackendMessage: CustomDebugStringConvertible {
    var debugDescription: String {
        switch self {
        case .accept(let accept):
            return ".accept(\(String(reflecting: accept)))"
        case .dataTypes:
            return ".dataTypes"
        case .error(let error):
            return ".error(\(String(reflecting: error))"
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
        case .describeInfo(let describeInfo):
            return ".describeInfo(\(String(reflecting: describeInfo)))"
        case .rowHeader(let header):
            return ".rowHeader(\(String(reflecting: header))"
        case .rowData(let data):
            return ".rowData(\(String(reflecting: data)))"
        case .queryParameter(let parameter):
            return ".queryParameter(\(String(reflecting: parameter))"
        }
    }
}
