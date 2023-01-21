struct RowID {
    let rba: UInt32
    let partitionID: UInt16
    let blockNumber: UInt32
    let slotNumber: UInt16

    static func read(from message: inout TNSMessage) -> RowID? {
        let rba = message.packet.readInteger(as: UInt32.self)
        let partitionID = message.packet.readInteger(as: UInt16.self)
        message.packet.moveReaderIndex(forwardByBytes: 1)
        let blockNumber = message.packet.readInteger(as: UInt32.self)
        let slotNumber = message.packet.readInteger(as: UInt16.self)
        guard let rba, let partitionID, let blockNumber, let slotNumber else { return nil }
        return RowID(rba: rba, partitionID: partitionID, blockNumber: blockNumber, slotNumber: slotNumber)
    }
}
