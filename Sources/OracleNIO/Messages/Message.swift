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
        self.connectString = "(DESCRIPTION=(CONNECT_DATA=(SERVICE_NAME=XEPDB1)(CID=(PROGRAM=xctest)(HOST=MacBook-Pro-von-Timo.local)(USER=timozacherl)))(ADDRESS=(PROTOCOL=tcp)(HOST=192.168.1.22)(PORT=1521)))"
    }

    func get() -> ByteBuffer {
        var serviceOptions = Constants.TNS_BASE_SERVICE_OPTIONS
        let connectFlags1: UInt32 = 0
        var connectFlags2: UInt32 = 0
        if connection.capabilities.supportsOOB == true {
            serviceOptions |= Constants.TNS_CAN_RECV_ATTENTION
            connectFlags2 |= Constants.TNS_CHECK_OOB
        }
        let connectStringByteLength = self.connectString.lengthOfBytes(using: .utf8)
        var buffer = ByteBuffer()
        buffer.startRequest(packetType: .connect)
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
            Constants.TNS_CONNECT_FLAGS,
            UInt64(0), // obsolete
            UInt64(0), // obsolete
            UInt64(0), // obsolete
            UInt32(Constants.TNS_SDU), // SDU (large)
            UInt32(Constants.TNS_TDU), // SDU (large)
            connectFlags1,
            connectFlags2
        )
        if connectStringByteLength > Constants.TNS_MAX_CONNECT_DATA {
            // TODO: this does not work yet
            buffer.endRequest(packetType: .connect)
            buffer.startRequest(packetType: .data)
        }
        buffer.writeString(self.connectString)
        buffer.endRequest(packetType: connectStringByteLength > Constants.TNS_MAX_CONNECT_DATA ? .data : .connect)
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
