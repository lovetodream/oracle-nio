import NIOCore

final class LOBOperationRequest: TNSRequest {
    var connection: OracleConnection
    var messageType: MessageType = .function
    var functionCode: UInt8 = Constants.TNS_FUNC_LOB_OP
    var currentSequenceNumber: UInt8 = 0
    var onResponsePromise: NIOCore.EventLoopPromise<TNSMessage>?

    var processedError = false
    var sourceOffset: UInt64 = 0
    var sourceLOB: LOB?
    var destinationOffset: UInt64 = 0
    var destinationLOB: LOB?
    var operation: UInt32 = 0
    var sendAmount = false
    var amount: Int64 = 0
    var data: [UInt8]?
    var boolFlag = false

    init(connection: OracleConnection, messageType: MessageType) {
        self.connection = connection
        self.messageType = messageType
    }

    func didProcessError() {
        processedError = true
    }

    func processResponse(_ message: inout TNSMessage, of type: MessageType, from channel: Channel) throws {
        if messageType == .lobData, let (bytes, _) = message.packet._readRawBytesAndLength() {
            if self.sourceLOB?.dbType.oracleType == .blob {
                self.data = bytes
            } else if let sourceLOB {
                let encoding = sourceLOB.encoding()
                // TODO: encode clob bytes using encoding
                self.data = bytes
            }
        }
    }

    func processReturnParameters(_ message: inout TNSMessage) {
        if let sourceLOB {
            let numberOfBytes = sourceLOB.locator.count
            let bytes = message.packet.readBytes(length: numberOfBytes)
            self.sourceLOB?.locator = bytes ?? []
        }
        if let destinationLOB {
            let numberOfBytes = destinationLOB.locator.count
            let bytes = message.packet.readBytes(length: numberOfBytes)
            self.destinationLOB?.locator = bytes ?? []
        }
        if self.operation == Constants.TNS_LOB_OP_CREATE_TEMP {
            message.packet.skipUB2() // skip character set
        }
        if self.sendAmount {
            self.amount = message.packet.readSB8() ?? 0
        }
        if self.operation == Constants.TNS_LOB_OP_CREATE_TEMP || self.operation == Constants.TNS_LOB_OP_IS_OPEN {
            let temp16 = message.packet.readUB2() ?? 0 // flag
            self.boolFlag = temp16 > 0
        }
    }

    func get() throws -> [TNSMessage] {
        var buffer = ByteBuffer()
        buffer.startRequest()
        self.writeFunctionCode(to: &buffer)

        if let sourceLOB {
            buffer.writeInteger(UInt8(1)) // source pointer
            buffer.writeUB4(UInt32(sourceLOB.locator.count))
        } else {
            buffer.writeInteger(UInt8(0)) // source pointer
            buffer.writeInteger(UInt8(0)) // source length
        }
        if let destinationLOB {
            buffer.writeInteger(UInt8(1)) // destination pointer
            buffer.writeUB4(UInt32(destinationLOB.locator.count))
        } else {
            buffer.writeInteger(UInt8(0)) // destination pointer
            buffer.writeInteger(UInt8(0)) // destination length
        }
        buffer.writeUB4(0) // short source offset
        buffer.writeUB4(0) // short destination offset
        buffer.writeInteger(UInt8(self.operation == Constants.TNS_LOB_OP_CREATE_TEMP ? 1 : 0)) // pointer (character set)
        buffer.writeInteger(UInt8(0)) // pointer (short amount)
        if self.operation == Constants.TNS_LOB_OP_CREATE_TEMP || self.operation == Constants.TNS_LOB_OP_IS_OPEN {
            buffer.writeInteger(UInt8(1)) // pointer (NULL LOB)
        } else {
            buffer.writeInteger(UInt8(0)) // pointer (NULL LOB)
        }
        buffer.writeUB4(self.operation)
        buffer.writeInteger(UInt8(0)) // pointer (SCN array)
        buffer.writeInteger(UInt8(0)) // SCN array length
        buffer.writeUB8(self.sourceOffset)
        buffer.writeUB8(self.destinationOffset)
        buffer.writeInteger(UInt8(self.sendAmount ? 1 : 0)) // pointer (amount)
        for _ in 0..<3 {
            buffer.writeInteger(UInt16(0)) // array LOB (not used)
        }
        if let sourceLOB {
            buffer.writeBytes(sourceLOB.locator)
        }
        if let destinationLOB {
            buffer.writeBytes(destinationLOB.locator)
        }
        if self.operation == Constants.TNS_LOB_OP_CREATE_TEMP {
            if let sourceLOB, sourceLOB.dbType.csfrm == Constants.TNS_CS_NCHAR {
                try self.connection.capabilities.checkNCharsetID()
                buffer.writeUB4(UInt32(Constants.TNS_CHARSET_UTF16))
            } else {
                buffer.writeUB4(UInt32(Constants.TNS_CHARSET_UTF8))
            }
        }
        if let data {
            buffer.writeInteger(MessageType.lobData.rawValue)
            buffer.writeBytesAndLength(data)
        }
        if self.sendAmount {
            buffer.writeUB8(UInt64(amount)) // LOB amount
        }
        buffer.endRequest(capabilities: self.connection.capabilities)
        return [.init(packet: buffer)]
    }

    func hasMoreData(_ message: inout TNSMessage) -> Bool {
        return !processedError
    }

    func initializeHooks() {
        self.functionCode = Constants.TNS_FUNC_LOB_OP
    }


}
