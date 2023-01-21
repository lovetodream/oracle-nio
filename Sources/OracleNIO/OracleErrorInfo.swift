import protocol Foundation.LocalizedError

struct OracleErrorInfo {
    var number: UInt32
    var cursorID: UInt16
    var position: UInt16
    var rowCount: UInt64
    var isWarning: Bool
    var message: String
    var rowID: Any
    var batchErrors: Array<Any>
}

enum OracleError: Int, Error, LocalizedError {
    // MARK: Error numbers that result in NotSupportedError
    case serverVersionNotSupported = 3010

    // MARK: Error Numbers that result in InternalError
    case unexpectedData = 5004

    // MARK: Error Numbers that result in OperationalError
    case listenerRefusedConnection = 6000

    var errorDescription: String? {
        switch self {
        case .serverVersionNotSupported:
            return "Connections to this database server version are not supported by oracle-nio."
        case .unexpectedData:
            return "Unexpected data received."
        case .listenerRefusedConnection:
            return "Cannot connect to database. Listener refused connection."
        }
    }
}
