//
//  File.swift
//  
//
//  Created by Timo Zacherl on 13.01.23.
//

import NIOCore

protocol TNSRequest {
    var connection: OracleConnection { get }
    var messageType: Int { get }
    var errorInfo: OracleErrorInfo? { get set }
    init(connection: OracleConnection, messageType: Int)
    static func initialize(from connection: OracleConnection) -> Self
    func initializeHooks()
    func get() -> [TNSMessage]
    func processResponse(_ message: inout TNSMessage, from channel: Channel) throws
}

extension TNSRequest {
    static func initialize(from connection: OracleConnection) -> Self {
        let message = Self.init(connection: connection, messageType: Constants.TNS_MSG_TYPE_FUNCTION)
        message.initializeHooks()
        return message
    }

    func initializeHooks() {}
    func processResponse(_ message: inout TNSMessage, from channel: Channel) throws {}
}

//struct AuthMessage: TNSRequest {
//
//}

struct NetworkServicesMessage: TNSRequest {
    var connection: OracleConnection
    var messageType: Int
    var errorInfo: OracleErrorInfo?

    init(connection: OracleConnection, messageType: Int) {
        self.connection = connection
        self.messageType = messageType
        self.errorInfo = nil
    }

    func get() -> [TNSMessage] {
        // Calculate package length
        var packetLength = NetworkService.Constants.TNS_NETWORK_HEADER_SIZE
        for service in NetworkService.all {
            packetLength += service.dataSize
        }

        var buffer = ByteBuffer()

        // Write header
        buffer.writeMultipleIntegers(NetworkService.Constants.TNS_NETWORK_MAGIC, UInt16(packetLength), NetworkService.Constants.TNS_NETWORK_VERSION, UInt16(NetworkService.all.count))
        buffer.writeInteger(0) // flags

        // Write service data
        for service in NetworkService.all {
            buffer.writeImmutableBuffer(service.writeData())
        }

        // TODO: find out how to handle service stuff
        return [.init(type: .data, packet: buffer)]
    }
}
