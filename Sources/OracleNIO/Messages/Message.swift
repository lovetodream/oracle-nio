//
//  File.swift
//  
//
//  Created by Timo Zacherl on 13.01.23.
//

import NIOCore

protocol Message {
    var connection: OracleConnection { get }
    var messageType: Int { get }
    var errorInfo: OracleErrorInfo? { get set }
    init(connection: OracleConnection, messageType: Int)
    static func initialize(from connection: OracleConnection) -> Self
    func initializeHooks()
    func get() -> ByteBuffer
}

extension Message {
    static func initialize(from connection: OracleConnection) -> Self {
        let message = Self.init(connection: connection, messageType: Constants.TNS_MSG_TYPE_FUNCTION)
        message.initializeHooks()
        return message
    }

    func initializeHooks() {}
}

struct ConnectMessage: Message {
    var connection: OracleConnection
    var messageType: Int
    var errorInfo: OracleErrorInfo?
    var connectString: String

    init(connection: OracleConnection, messageType: Int) {
        self.connection = connection
        self.messageType = messageType
        self.errorInfo = nil
        self.connectString = "//whitewolf.witchers.tech:1521/XEPDB1"
    }

    func get() -> ByteBuffer {
        let connectFlags1: UInt32 = 0
        let connectFlags2: UInt32 = 0
        var buffer = ByteBuffer()
        buffer.startRequest(packetType: Constants.TNS_PACKET_TYPE_CONNECT)
        buffer.writeMultipleIntegers(
            Constants.TNS_VERSION_DESIRED,
            Constants.TNS_VERSION_MINIMUM,
            Constants.TNS_BASE_SERVICE_OPTIONS,
            Constants.TNS_SDU,
            Constants.TNS_TDU,
            Constants.TNS_PROTOCOL_CHARACTERISTICS,
            UInt16(0), // line turnaround
            UInt16(1), // value of 1
            UInt16(self.connectString.count)
        )
        buffer.writeMultipleIntegers(
            UInt16(74), // offset to connect data
            UInt32(0), // max receivable data
            Constants.TNS_CONNECT_FLAGS,
            UInt64(0), // obsolete
            UInt64(0), // obsolete
            UInt64(0), // obsolete
            UInt32(Constants.TNS_SDU), // SDU (large)
            UInt32(Constants.TNS_TDU), // SDU (large)
            connectFlags1,
            connectFlags2
        )
        if self.connectString.count > Constants.TNS_MAX_CONNECT_DATA {
            buffer.endRequest()
            buffer.startRequest(packetType: Constants.TNS_PACKET_TYPE_DATA)
        }
        buffer.writeString(self.connectString)
        buffer.endRequest()
        return buffer
    }
}

struct NetworkServicesMessage: Message {
    var connection: OracleConnection
    var messageType: Int
    var errorInfo: OracleErrorInfo?

    init(connection: OracleConnection, messageType: Int) {
        self.connection = connection
        self.messageType = messageType
        self.errorInfo = nil
    }

    func get() -> ByteBuffer {
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

        return buffer
    }
}
