import NIOCore

protocol NetworkServiceProtocol {
    var dataSize: UInt16 { get }
    func writeData() -> ByteBuffer
    func writeHeader(service: NetworkServiceType, numberOfSubPackets: UInt16) -> ByteBuffer
    func writeVersion() -> ByteBuffer
}

extension NetworkServiceProtocol {
    var dataSize: UInt16 { NetworkService.Constants.TNS_NETWORK_HEADER_SIZE }

    func writeHeader(service: NetworkServiceType, numberOfSubPackets: UInt16) -> ByteBuffer {
        var buffer = ByteBuffer()
        buffer.writeMultipleIntegers(service.rawValue, numberOfSubPackets, UInt32(0))
        return buffer
    }

    func writeVersion() -> ByteBuffer {
        var buffer = ByteBuffer()
        buffer.writeMultipleIntegers(
            UInt16(4),
            NetworkService.Constants.TNS_NETWORK_TYPE_VERSION,
            NetworkService.Constants.TNS_NETWORK_VERSION
        )
        return buffer
    }
}

struct AuthenticationService: NetworkServiceProtocol {
    var dataSize: UInt16 { NetworkService.Constants.TNS_NETWORK_SERVICE_HEADER_SIZE + 8 + 6 + 6 }

    func writeData() -> ByteBuffer {
        var buffer = ByteBuffer()
        buffer.writeImmutableBuffer(self.writeHeader(service: .auth, numberOfSubPackets: 3))
        buffer.writeImmutableBuffer(self.writeVersion())

        // write auth type
        buffer.writeInteger(UInt16(2)) // length
        buffer.writeMultipleIntegers(
            NetworkService.Constants.TNS_NETWORK_TYPE_UB2,
            NetworkService.Constants.TNS_NETWORK_AUTH_TYPE_CLIENT_SERVER
        )

        // write status
        buffer.writeInteger(UInt16(2)) // length
        buffer.writeMultipleIntegers(
            NetworkService.Constants.TNS_NETWORK_TYPE_STATUS,
            NetworkService.Constants.TNS_NETWORK_AUTH_STATUS_NOT_REQUIRED
        )
        return buffer
    }
}

struct DataIntegrityService: NetworkServiceProtocol {
    var dataSize: UInt16 { NetworkService.Constants.TNS_NETWORK_SERVICE_HEADER_SIZE + 8 + 5 }

    func writeData() -> ByteBuffer {
        var buffer = ByteBuffer()
        buffer.writeImmutableBuffer(self.writeHeader(service: .dataIntegrity, numberOfSubPackets: 2))
        buffer.writeImmutableBuffer(self.writeVersion())

        // write options
        buffer.writeMultipleIntegers(
            UInt16(1),
            NetworkService.Constants.TNS_NETWORK_TYPE_RAW,
            NetworkService.Constants.TNS_NETWORK_DATA_INTEGRITY_NONE
        )
        return buffer
    }
}

struct EncryptionService: NetworkServiceProtocol {
    var dataSize: UInt16 { NetworkService.Constants.TNS_NETWORK_SERVICE_HEADER_SIZE + 8 + 5 }

    func writeData() -> ByteBuffer {
        var buffer = ByteBuffer()
        buffer.writeImmutableBuffer(self.writeHeader(service: .encryption, numberOfSubPackets: 2))
        buffer.writeImmutableBuffer(self.writeVersion())

        // write options
        buffer.writeMultipleIntegers(
            UInt16(1),
            NetworkService.Constants.TNS_NETWORK_TYPE_RAW,
            NetworkService.Constants.TNS_NETWORK_ENCRYPTION_NULL
        )
        return buffer
    }
}

struct SupervisorService: NetworkServiceProtocol {
    var dataSize: UInt16 { NetworkService.Constants.TNS_NETWORK_SERVICE_HEADER_SIZE + 8 + 12 + 22 }

    func writeData() -> ByteBuffer {
        var buffer = ByteBuffer()
        buffer.writeImmutableBuffer(self.writeHeader(service: .supervisor, numberOfSubPackets: 3))
        buffer.writeImmutableBuffer(self.writeVersion())

        // write CID
        buffer.writeMultipleIntegers(
            UInt16(8),
            NetworkService.Constants.TNS_NETWORK_TYPE_RAW,
            NetworkService.Constants.TNS_NETWORK_SUPERVISOR_CID
        )

        // write supervised services array
        buffer.writeMultipleIntegers(
            UInt16(18),
            NetworkService.Constants.TNS_NETWORK_TYPE_RAW,
            NetworkService.Constants.TNS_NETWORK_MAGIC,
            NetworkService.Constants.TNS_NETWORK_TYPE_UB2,
            UInt32(4),
            NetworkServiceType.supervisor.rawValue,
            NetworkServiceType.auth.rawValue,
            NetworkServiceType.encryption.rawValue,
            NetworkServiceType.dataIntegrity.rawValue
        )
        return buffer
    }
}

/// TNS Network service numbers
enum NetworkServiceType: UInt16, CustomStringConvertible {
    case auth = 1
    case encryption = 2
    case dataIntegrity = 3
    case supervisor = 4

    var description: String {
        switch self {
        case .auth:
            return "AUTH"
        case .encryption:
            return "ENCRYPTION"
        case .dataIntegrity:
            return "DATA_INTEGRITY"
        case .supervisor:
            return "SUPERVISOR"
        }
    }
}

enum NetworkService {
    static let all: [NetworkServiceProtocol] =
        [SupervisorService(), AuthenticationService(), EncryptionService(), DataIntegrityService()]

    enum Constants {
        /// Magic value used to recognize network data.
        static let TNS_NETWORK_MAGIC: UInt32 = 0xDEADBEEF
        /// Version used for network packets (11.2.0.2.0).
        static let TNS_NETWORK_VERSION: UInt32 = 0xB200200

        // MARK: Network data types
        static let TNS_NETWORK_TYPE_RAW: UInt16 = 1
        static let TNS_NETWORK_TYPE_UB2: UInt16 = 3
        static let TNS_NETWORK_TYPE_VERSION: UInt16 = 5
        static let TNS_NETWORK_TYPE_STATUS: UInt16 = 6

        // MARK: Network header sizes
        static let TNS_NETWORK_HEADER_SIZE: UInt16 = 4 + 2 + 4 + 2 + 1
        static let TNS_NETWORK_SERVICE_HEADER_SIZE: UInt16 = 2 + 2 + 4

        // MARK: Network supervisor service constants
        static let TNS_NETWORK_SUPERVISOR_CID: UInt64 = 0x0000101C66EC28EA

        // MARK: Network authentication service constants
        static let TNS_NETWORK_AUTH_TYPE_CLIENT_SERVER: UInt16 = 0xE0E1
        static let TNS_NETWORK_AUTH_STATUS_NOT_REQUIRED: UInt16 = 0xFCFF

        // MARK: Network data integrity service constants
        static let TNS_NETWORK_DATA_INTEGRITY_NONE: UInt8 = 0

        // MARK: Network encryption service constants
        static let TNS_NETWORK_ENCRYPTION_NULL: UInt8 = 0
    }
}
