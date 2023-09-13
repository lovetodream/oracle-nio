import NIOCore

/// A protocol to implement for all associated values in the ``OracleBackendMessage`` enum.
protocol OracleMessagePayloadDecodable {
    /// Decodes the associated value for a ``OracleBackendMessage`` from the given
    /// `ByteBuffer`.
    ///
    /// When the decoding is done all bytes in the given ``ByteBuffer`` must be consumed.
    /// ``ByteBuffer.readableBytes`` must be `0`. In case of an error a
    /// ``OraclePartialDecodingError`` must be thrown.
    ///
    /// - Parameter buffer: The ``ByteBuffer`` to read the message from. When done the
    ///                     `ByteBuffer` must be fully consumed.
    static func decode(
        from buffer: inout ByteBuffer,
        capabilities: Capabilities
    ) throws -> Self
}

/// A wire message that is created by a Oracle server to be consumed by the Oracle client.
enum OracleBackendMessage: Sendable, Hashable {
    typealias PayloadDecodable = OracleMessagePayloadDecodable

    case accept(Accept)
    case bitVector(BitVector)
    case dataTypes
    case describeInfo(DescribeInfo)
    case error(BackendError)
    case marker
    case lobData(LOBData)
    case parameter(Parameter)
    case `protocol`(`Protocol`)
    case queryParameter(QueryParameter)
    case resend
    case rowHeader(RowHeader)
    case rowData(RowData)
    case serverSidePiggyback(ServerSidePiggyback)
    case status(Status)
    case warning(BackendError)

    case chunk(ByteBuffer)
}

extension OracleBackendMessage {
    /// Equivalent to ``PacketType``.
    enum ID: UInt8, Equatable {
        case accept = 2
        case data = 6
        case resend = 11
        case marker = 12
    }

    /// Equivalent to ``MessageType``.
    enum MessageID: UInt8, Equatable {
        case `protocol` = 1
        case dataTypes = 2
        case error = 4
        case rowHeader = 6
        case rowData = 7
        case parameter = 8
        case status = 9
        case lobData = 14
        case warning = 15
        case describeInfo = 16
        case bitVector = 21
        case serverSidePiggyback = 23
    }
}

extension OracleBackendMessage {
    static func decode(
        from buffer: inout ByteBuffer,
        of packetID: ID,
        capabilities: Capabilities,
        skipDataFlags: Bool = true,
        queryOptions: QueryOptions? = nil,
        isChunkedRead: Bool
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
            if isChunkedRead {
                messages.append(.chunk(buffer.slice()))
            } else {
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
                        messages.append(try .status(
                            .decode(from: &buffer, capabilities: capabilities)
                        ))
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
                    case .bitVector:
                        messages.append(try .bitVector(
                            .decode(from: &buffer, capabilities: capabilities)
                        ))
                    case .warning:
                        messages.append(try .warning(
                            .decodeWarning(
                                from: &buffer, capabilities: capabilities
                            )
                        ))
                    case .serverSidePiggyback:
                        messages.append(try .serverSidePiggyback(
                            .decode(from: &buffer, capabilities: capabilities)
                        ))
                    case .lobData:
                        messages.append(try .lobData(
                            .decode(from: &buffer, capabilities: capabilities)
                        ))
                    case nil:
                        throw OraclePartialDecodingError
                            .unknownMessageIDReceived(messageID: messageIDByte)
                    }
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
        case .bitVector(let bitVector):
            return ".bitVector(\(String(reflecting: bitVector)))"
        case .dataTypes:
            return ".dataTypes"
        case .error(let error):
            return ".error(\(String(reflecting: error)))"
        case .marker:
            return ".marker"
        case .parameter(let parameter):
            return ".parameter(\(String(reflecting: parameter)))"
        case .protocol(let `protocol`):
            return ".protocol(\(String(reflecting: `protocol`)))"
        case .resend:
            return ".resend"
        case .status(let status):
            return ".status(\(String(reflecting: status)))"
        case .describeInfo(let describeInfo):
            return ".describeInfo(\(String(reflecting: describeInfo)))"
        case .rowHeader(let header):
            return ".rowHeader(\(String(reflecting: header))"
        case .rowData(let data):
            return ".rowData(\(String(reflecting: data)))"
        case .queryParameter(let parameter):
            return ".queryParameter(\(String(reflecting: parameter)))"
        case .warning(let warning):
            return ".warning(\(String(reflecting: warning))"
        case .chunk(let buffer):
            return ".chunk(\(String(reflecting: buffer)))"
        case .serverSidePiggyback(let piggyback):
            return ".serverSidePiggyback(\(String(reflecting: piggyback)))"
        case .lobData(let data):
            return ".lobData(\(String(reflecting: data)))"
        }
    }
}
