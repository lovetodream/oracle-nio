import NIOCore

extension ByteBuffer {
    mutating func readSB1() -> Int8? {
        readInteger(as: Int8.self)
    }

    mutating func readSB2() -> Int16? {
        guard let length = readUBLength() else { return nil }
        switch length {
        case 0:
            return 0
        case 1:
            return self.readInteger(as: Int8.self).map(Int16.init(_:))
        case 2:
            return self.readInteger(as: Int16.self)
        default:
            fatalError()
        }
    }
}
