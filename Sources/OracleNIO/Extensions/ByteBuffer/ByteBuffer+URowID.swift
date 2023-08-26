import NIOCore

extension ByteBuffer {
    mutating func readUniversalRowID() -> String? {
        // Get data (first buffer contains the length, which can be ignored)
        guard let (bytes1, _) = self._readRawBytesAndLength(), bytes1 != nil else { return nil }
        guard let (bytes, lengthTmp) =  self._readRawBytesAndLength(), let bytes else { return nil }
        var length = lengthTmp
        var buffer = ByteBuffer(bytes: bytes)

        var rowID = RowID()

        // handle phyiscal rowid
        if buffer.readBytes(length: 1) == [1] {
            rowID.rba = buffer.readInteger(endianness: .big, as: UInt32.self) ?? 0
            rowID.partitionID = buffer.readInteger(endianness: .big, as: UInt16.self) ?? 0
            rowID.blockNumber = buffer.readInteger(endianness: .big, as: UInt32.self) ?? 0
            rowID.slotNumber = buffer.readInteger(endianness: .big, as: UInt16.self) ?? 0
            return rowID.description
        }

        // handle logical rowID
        var outputLength = length / 3 * 4
        let remainder = length % 3
        if remainder == 1 {
            outputLength += 1
        } else if remainder == 2 {
            outputLength += 3
        }
        var outputValue = [UInt8](repeating: 0, count: Int(outputLength))
        length -= 1
        outputValue[0] = 42
        var outputOffset = 1
        var inputOffset = 1

        while length > 0 {
            // produce first byte of quadruple
            var position = bytes[inputOffset] >> 2
            outputValue[outputOffset] = Constants.TNS_BASE64_ALPHABET_ARRAY[Int(position)]
            outputOffset += 1

            // produce second byte of quadruple, but if only one byte is left, produce that one byte and exit
            position = (bytes[inputOffset] & 0x3) << 4
            if length == 1 {
                outputValue[outputOffset] = Constants.TNS_BASE64_ALPHABET_ARRAY[Int(position)]
                break
            }
            inputOffset += 1
            position |= ((bytes[inputOffset] & 0xf0) >> 4)
            outputValue[outputOffset] = Constants.TNS_BASE64_ALPHABET_ARRAY[Int(position)]
            outputOffset += 1

            // produce third byte of quadruple, but if only two bytes are left, produce that one byte and exit
            position = (bytes[inputOffset] & 0xf) << 2
            if length == 2 {
                outputValue[outputOffset] = Constants.TNS_BASE64_ALPHABET_ARRAY[Int(position)]
                break
            }
            inputOffset += 1
            position |= ((bytes[inputOffset] & 0xc0) >> 6)
            outputValue[outputOffset] = Constants.TNS_BASE64_ALPHABET_ARRAY[Int(position)]
            outputOffset += 1

            // produce final byte of quadruple
            position = bytes[inputOffset] & 0x3f
            outputValue[outputOffset] = Constants.TNS_BASE64_ALPHABET_ARRAY[Int(position)]
            outputOffset += 1
            inputOffset += 1
            length -= 3
        }
        return String(cString: outputValue)
    }
}
