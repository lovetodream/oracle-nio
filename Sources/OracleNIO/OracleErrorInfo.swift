import protocol Foundation.LocalizedError

struct OracleErrorInfo: Error {
    var number: UInt32
    var cursorID: UInt16?
    var position: UInt16?
    var rowCount: UInt64?
    var isWarning: Bool
    var message: String?
    var rowID: RowID?
    var batchErrors: [OracleError]
}

struct OracleError: Error {
    var code: Int
    var offset: Int
    var message: String?

    init(message: String? = nil, code: Int = 0, offset: Int = 0) {
        self.code = code
        self.offset = offset
        self.message = message
    }

    enum ErrorType: Int, Error, LocalizedError {
        // MARK: Error numbers that result in InterfaceError
        case poolHasBusyConnections = 1005

        // MARK: Error numbers that result in ProgrammingError
        case invalidObjectTypeName = 2035
        case invalidCollectionIndexSet = 2039

        // MARK: Error numbers that result in NotSupportedError
        case serverVersionNotSupported = 3010

        // MARK: Error numbers that result in DatabaseError
        case noCredentials = 4001
        case poolNoConnectionAvailable = 4005
        case arrayDMLRowCountsNotEnabled = 4006
        case connectionClosed = 4011
        case invalidRefCursor = 4025

        // MARK: Error Numbers that result in InternalError
        case typeUnknown = 5000
        case unexpectedData = 5004

        // MARK: Error Numbers that result in OperationalError
        case listenerRefusedConnection = 6000

        var errorDescription: String? {
            switch self {
            case .poolHasBusyConnections:
                return "Connection pool cannot be closed because connections are busy."
            case .invalidObjectTypeName:
                return "Invalid object type name."
            case .invalidCollectionIndexSet:
                return "Given index is out of range."
            case .serverVersionNotSupported:
                return "Connections to this database server version are not supported by oracle-nio."
            case .noCredentials:
                return "No credentials specified."
            case .poolNoConnectionAvailable:
                return "Timed out waiting for the connection pool to return a connection."
            case .arrayDMLRowCountsNotEnabled:
                return "Array DML row counts mode is not enabled."
            case .connectionClosed:
                return "The database or network closed the connection."
            case .invalidRefCursor:
                return "Invalid REF cursor: never opened in PL/SQL."
            case .typeUnknown:
                return "Internal error: unknown protocol message type."
            case .unexpectedData:
                return "Unexpected data received."
            case .listenerRefusedConnection:
                return "Cannot connect to database. Listener refused connection."
            }
        }
    }

    /// Oracle error number cross reference
    private static let oracleErrorXref: [Int: OracleError.ErrorType] = [
        28: .connectionClosed,
        600: .connectionClosed,
        1005: .noCredentials,
        22165: .invalidCollectionIndexSet,
        22303: .invalidObjectTypeName,
        24422: .poolHasBusyConnections,
        24349: .arrayDMLRowCountsNotEnabled,
        24459: .poolNoConnectionAvailable,
        24496: .poolNoConnectionAvailable,
        24338: .invalidRefCursor,
    ]
}
