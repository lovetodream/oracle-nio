import struct NIOCore.ByteBuffer

extension ByteBuffer {
    mutating func readUB2() -> UInt16? {
        guard let length = readUBLength() else { return nil }
        switch length {
        case 0:
            return 0
        case 1:
            return self.readInteger(as: UInt8.self).map(UInt16.init(_:))
        case 2:
            return self.readInteger(as: UInt16.self)
        default:
            fatalError()
        }
    }

    mutating func readUB4() -> UInt32? {
        guard let length = readUBLength() else { return nil }
        switch length {
        case 0:
            return 0
        case 1:
            return self.readInteger(as: UInt8.self).map(UInt32.init(_:))
        case 2:
            return self.readInteger(as: UInt16.self).map(UInt32.init(_:))
        case 4:
            return self.readInteger(as: UInt32.self)
        default:
            fatalError()
        }
    }

    mutating func skipUB4() {
        guard let length = readUBLength() else { return }
        guard length <= 4 else { fatalError() }
        self.moveReaderIndex(forwardByBytes: Int(length))
    }

    private mutating func readUBLength() -> UInt8? {
        guard let first = self.readBytes(length: 1)?.first else { return nil }
        let length: UInt8
        if first & 0x80 != 0 {
            length = first & 0x7f
        } else {
            length = first
        }
        return length
    }

    mutating func writeUB4(_ integer: UInt32) {
        switch integer {
        case 0:
            self.writeInteger(UInt8(0))
        case 1...UInt32(UInt8.max):
            self.writeInteger(UInt8(1))
            self.writeInteger(UInt8(integer))
        case (UInt32(UInt8.max) + 1)...UInt32(UInt16.max):
            self.writeInteger(UInt8(2))
            self.writeInteger(UInt16(integer))
        default:
            self.writeInteger(UInt8(4))
            self.writeInteger(integer)
        }
    }
}
