import NIOCore

extension ByteBuffer {
    mutating func readRowID() -> RowID {
        let rba = self.readUB4()
        let partitionID = self.readUB2()
        self.skipUB1()
        let blockNumber = self.readUB4()
        let slotNumber = self.readUB2()
        return RowID(
            rba: rba ?? 0,
            partitionID: partitionID ?? 0,
            blockNumber: blockNumber ?? 0,
            slotNumber: slotNumber ?? 0
        )
    }
}
