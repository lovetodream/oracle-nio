import NIOCore

extension ByteBuffer {
    mutating func readRowIDSlice() -> ByteBuffer {
        let rba = self.readUB4() ?? 0
        let placeholder = self.readUB1() ?? 0
        let blockNumber = self.readUB4() ?? 0
        let slotNumber = self.readUB2() ?? 0

        var buffer = ByteBuffer()
        buffer.writeMultipleIntegers(rba, placeholder, blockNumber, slotNumber)
        return buffer
    }

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
