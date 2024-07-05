//===----------------------------------------------------------------------===//
//
// This source file is part of the OracleNIO open source project
//
// Copyright (c) 2024 Timo Zacherl and the OracleNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
// See CONTRIBUTORS.md for the list of OracleNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

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
    ///  - Throws: ``OraclePartialDecodingError`` if decoding failed or
    ///          ``MissingDataDecodingError`` if more data is required to continue decoding.
    static func decode(
        from buffer: inout ByteBuffer,
        context: OracleBackendMessageDecoder.Context
    ) throws -> Self
}

/// A wire message that is created by a Oracle server to be consumed by the Oracle client.
enum OracleBackendMessage: Sendable, Hashable {
    typealias PayloadDecodable = OracleMessagePayloadDecodable

    case accept(Accept)
    case bitVector(BitVector)
    case dataTypes(DataTypes)
    case describeInfo(DescribeInfo)
    case error(BackendError)
    case marker
    case lobData(LOBData)
    case parameter(Parameter)
    case `protocol`(`Protocol`)
    case queryParameter(QueryParameter)
    case lobParameter(LOBParameter)
    case resend
    case rowHeader(RowHeader)
    case rowData(RowData)
    case serverSidePiggyback(ServerSidePiggyback)
    case status(Status)
    case warning(BackendError)
    case ioVector(InOutVector)
    case flushOutBinds
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
        case ioVector = 11
        case lobData = 14
        case warning = 15
        case describeInfo = 16
        case flushOutBinds = 19
        case bitVector = 21
        case serverSidePiggyback = 23
        case endOfRequest = 29
    }
}

extension OracleBackendMessage {
    static func decode(
        from buffer: inout ByteBuffer,
        of packetID: ID,
        context: OracleBackendMessageDecoder.Context
    ) throws -> (TinySequence<OracleBackendMessage>, lastPacket: Bool) {
        switch packetID {
        case .resend:
            return (.init(element: .resend), true)
        case .accept:
            return (
                .init(
                    element:
                        try .accept(.decode(from: &buffer, context: context))), true
            )
        case .marker:
            return (.init(element: .marker), true)
        case .data:
            var messages: TinySequence<OracleBackendMessage> = []
            let flags = try buffer.throwingReadInteger(as: UInt16.self)
            let lastPacket = (flags & Constants.TNS_DATA_FLAGS_END_OF_REQUEST) != 0
            try self.decodeData(from: &buffer, into: &messages, context: context)
            return (messages, lastPacket)
        }
    }

    static func decodeData(
        from buffer: inout ByteBuffer,
        into messages: inout TinySequence<OracleBackendMessage>,
        context: OracleBackendMessageDecoder.Context
    ) throws {
        readLoop: while buffer.readableBytes > 0 {
            let savePoint = buffer.readerIndex
            let messageIDByte = try buffer.throwingReadInteger(as: UInt8.self)
            let messageID = MessageID(rawValue: messageIDByte)
            do {
                switch messageID {
                case .dataTypes:
                    messages.append(
                        try .dataTypes(.decode(from: &buffer, context: context))
                    )
                    if !context.capabilities.supportsEndOfRequest {
                        break readLoop
                    }
                case .protocol:
                    messages.append(
                        try .protocol(.decode(from: &buffer, context: context))
                    )
                    if !context.capabilities.supportsEndOfRequest {
                        break readLoop
                    }
                case .error:
                    let error = try BackendError.decode(from: &buffer, context: context)
                    // not ideal but the most reliable way I could come up with
                    if error.number != 0 { context.clearStatementContext() }
                    messages.append(.error(error))
                    // error marks the end of response if no explicit end of
                    // response is available
                    if !context.capabilities.supportsEndOfRequest {
                        break readLoop
                    }
                case .parameter:
                    if context.lobContext != nil {
                        messages.append(
                            try .lobParameter(.decode(from: &buffer, context: context))
                        )
                    } else {
                        switch context.statementContext {
                        case .some:
                            messages.append(
                                try .queryParameter(.decode(from: &buffer, context: context))
                            )
                        case .none:
                            messages.append(
                                try .parameter(.decode(from: &buffer, context: context))
                            )
                            break readLoop
                        }
                    }

                case .status:
                    messages.append(
                        try .status(.decode(from: &buffer, context: context))
                    )
                    if !context.capabilities.supportsEndOfRequest {
                        break readLoop
                    }
                case .ioVector:
                    messages.append(
                        try .ioVector(.decode(from: &buffer, context: context))
                    )
                case .describeInfo:
                    let describeInfo = try DescribeInfo.decode(from: &buffer, context: context)
                    context.describeInfo = describeInfo
                    messages.append(.describeInfo(describeInfo))

                case .rowHeader:
                    let rowHeader = try RowHeader.decode(from: &buffer, context: context)
                    context.bitVector = rowHeader.bitVector
                    messages.append(.rowHeader(rowHeader))

                case .rowData:
                    messages.append(
                        try .rowData(.decode(from: &buffer, context: context))
                    )

                case .bitVector:
                    let bitVector = try BitVector.decode(from: &buffer, context: context)
                    context.bitVector = bitVector.bitVector
                    messages.append(.bitVector(bitVector))

                case .warning:
                    messages.append(
                        try .warning(.decodeWarning(from: &buffer, context: context))
                    )
                case .serverSidePiggyback:
                    messages.append(
                        try .serverSidePiggyback(.decode(from: &buffer, context: context))
                    )
                case .lobData:
                    messages.append(
                        try .lobData(.decode(from: &buffer, context: context))
                    )
                case .flushOutBinds:
                    messages.append(.flushOutBinds)
                case .endOfRequest:
                    break readLoop
                case nil:
                    throw
                        OraclePartialDecodingError
                        .unknownMessageIDReceived(messageID: messageIDByte)
                }
            } catch is MissingDataDecodingError.Trigger {
                throw MissingDataDecodingError(
                    decodedMessages: messages, resetToReaderIndex: savePoint)
            }
        }
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
        case .lobParameter(let parameter):
            return ".lobParameter(\(String(reflecting: parameter)))"
        case .warning(let warning):
            return ".warning(\(String(reflecting: warning))"
        case .serverSidePiggyback(let piggyback):
            return ".serverSidePiggyback(\(String(reflecting: piggyback)))"
        case .lobData(let data):
            return ".lobData(\(String(reflecting: data)))"
        case .ioVector(let vector):
            return ".ioVector(\(String(reflecting: vector)))"
        case .flushOutBinds:
            return ".flushOutBinds"
        }
    }
}
