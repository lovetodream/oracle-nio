import NIOCore
import struct Foundation.UUID

struct ConnectionCookieManager: Sendable {
    static var shared = ConnectionCookieManager()

    private var store: [String: ConnectionCookie] = [:]

    private init() { }

    func get(
        by uuid: UUID, description: Description
    ) -> ConnectionCookie? {
        let key = uuid.uuidString +
            (description.serviceName ?? description.sid ?? "")
        return store[key]
    }

    func set() {
        // TOOD
    }
}

struct ConnectionCookie: Sendable {
    var protocolVersion: UInt8
    var serverBanner: ByteBuffer
    var charsetID: UInt16
    var nationalCharsetID: UInt16
    var flags: UInt8
    var compileCapabilities: ByteBuffer
    var runtimeCapabilities: ByteBuffer
    var populated: Bool
}
