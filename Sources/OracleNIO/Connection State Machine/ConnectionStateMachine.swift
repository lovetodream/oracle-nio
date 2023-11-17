import NIOCore
import struct Foundation.TimeZone

struct ConnectionStateMachine {
    enum State {
        case initialized
        case connectMessageSent
        case protocolMessageSent
        case dataTypesMessageSent
        case waitingToStartAuthentication
        case authenticating(AuthenticationStateMachine)
        case readyForQuery
        case extendedQuery(ExtendedQueryStateMachine)
        case ping(EventLoopPromise<Void>)
        case commit(EventLoopPromise<Void>)
        case rollback(EventLoopPromise<Void>)
        /// Set by ``ConnectionAction.closeConnectionAndCleanup(_:)`` to prepare us for
        /// the upcoming ``loggingOff`` state.
        case readyToLogOff
        case loggingOff(EventLoopPromise<Void>?)
        case closing
        case closed

        case renegotiatingTLS

        case modifying
    }

    enum QuiescingState {
        case notQuiescing
        case quiescing(closePromise: EventLoopPromise<Void>?)
    }

    enum MarkerState {
        case noMarkerSent
        case markerSent
    }

    enum ConnectionAction {

        struct CleanUpContext {
            enum Action {
                case close
                case fireChannelInactive
            }

            let action: Action

            /// Tasks to fail with the error
            let tasks: [OracleTask]

            let error: OracleSQLError

            let closePromise: EventLoopPromise<Void>?
        }

        case read
        case wait
        case logoffConnection(EventLoopPromise<Void>?)
        case closeConnection(EventLoopPromise<Void>?)
        case fireChannelInactive
        case fireEventReadyForQuery

        /// Close connection because of an error state. Fail all tasks with the provided error.
        case closeConnectionAndCleanup(CleanUpContext)

        // Connection Establishment Actions
        case sendConnect
        case sendProtocol
        case sendDataTypes

        // Authentication Actions
        case provideAuthenticationContext(ConnectionCookie?)
        case sendAuthenticationPhaseOne(AuthContext, ConnectionCookie?)
        case sendAuthenticationPhaseTwo(
            AuthContext, OracleBackendMessage.Parameter
        )
        case authenticated(OracleBackendMessage.Parameter)

        // Ping
        case sendPing
        case failPing(EventLoopPromise<Void>, with: OracleSQLError)
        case succeedPing(EventLoopPromise<Void>)

        // Commit/Rollback
        case sendCommit
        case failCommit(EventLoopPromise<Void>, with: OracleSQLError)
        case succeedCommit(EventLoopPromise<Void>)
        case sendRollback
        case failRollback(EventLoopPromise<Void>, with: OracleSQLError)
        case succeedRollback(EventLoopPromise<Void>)

        // Query
        case sendExecute(ExtendedQueryContext, DescribeInfo?)
        case sendReexecute(ExtendedQueryContext, CleanupContext)
        case sendFetch(ExtendedQueryContext)
        case failQuery(
            EventLoopPromise<OracleRowStream>,
            with: OracleSQLError, cleanupContext: CleanUpContext?
        )
        case succeedQuery(EventLoopPromise<OracleRowStream>, QueryResult)
        case needMoreData

        // Query streaming
        case forwardRows([DataRow])
        case forwardStreamComplete([DataRow], cursorID: UInt16)
        case forwardStreamError(
            OracleSQLError, read: Bool, cursorID: UInt16?, clientCancelled: Bool
        )

        case sendMarker
    }

    private var state: State
    private var taskQueue = CircularBuffer<OracleTask>()
    private var quiescingState: QuiescingState = .notQuiescing
    private var markerState: MarkerState = .noMarkerSent

    init() {
        self.state = .initialized
    }

    mutating func connected() -> ConnectionAction {
        switch self.state {
        case .initialized:
            self.state = .connectMessageSent
            return .sendConnect
        default:
            return .wait
        }
    }

    mutating func provideAuthenticationContext(
        _ authContext: AuthContext, cookie: ConnectionCookie?
    ) -> ConnectionAction {
        self.startAuthentication(authContext, cookie: cookie)
    }

    mutating func close(
        _ promise: EventLoopPromise<Void>?
    ) -> ConnectionAction {
        return self.closeConnectionAndCleanup(
            .clientClosedConnection(underlying: nil),
            closePromise: promise
        )
    }

    mutating func closed() -> ConnectionAction {
        switch self.state {
        case .initialized:
            preconditionFailure(
                "How can a connection be closed, if it was never connected."
            )
        case .connectMessageSent,
             .protocolMessageSent,
             .dataTypesMessageSent,
             .waitingToStartAuthentication,
             .authenticating,
             .readyForQuery,
             .extendedQuery,
             .ping,
             .commit,
             .rollback,
             .readyToLogOff,
             .renegotiatingTLS:
            return self.errorHappened(.uncleanShutdown)
        case .loggingOff, .closing:
            self.state = .closed
            self.quiescingState = .notQuiescing
            return .fireChannelInactive
        case .closed:
            preconditionFailure(
                "How can a connection be closed, if it is already closed."
            )

        case .modifying:
            preconditionFailure("Invalid state")
        }
    }

    mutating func errorHappened(_ error: OracleSQLError) -> ConnectionAction {
        switch self.state {
        case .connectMessageSent,
             .dataTypesMessageSent,
             .protocolMessageSent,
             .waitingToStartAuthentication,
             .initialized,
             .readyForQuery,
             .ping,
             .commit,
             .rollback,
             .renegotiatingTLS:
            return self.closeConnectionAndCleanup(error)
        case .authenticating(var authState):
            let action = authState.errorHappened(error)
            return self.modify(with: action)
        case .extendedQuery(var queryState):
            if queryState.isComplete {
                return self.closeConnectionAndCleanup(error)
            } else {
                let action = queryState.errorHappened(error)
                return self.modify(with: action)
            }
        case .readyToLogOff, .loggingOff, .closing:
            // If the state machine is in state `.closing`, the connection
            // shutdown was initiated by the client. This means a `TERMINATE`
            // message has already been sent and the connection close was passed
            // on to the channel. Therefore we await a channelInactive as the
            // next event.
            // Since a connection close was already issued we should keep cool
            // and just wait.
            return .wait
        case .closed:
            return self.closeConnectionAndCleanup(error)

        case .modifying:
            preconditionFailure("Invalid state")
        }
    }

    mutating func enqueue(task: OracleTask) -> ConnectionAction {
        let oracleError: OracleSQLError

        switch self.quiescingState {
        case .quiescing:
            oracleError = .clientClosesConnection(underlying: nil)

        case .notQuiescing:
            switch self.state {
            case .initialized,
                 .connectMessageSent,
                 .protocolMessageSent,
                 .dataTypesMessageSent,
                 .waitingToStartAuthentication,
                 .authenticating,
                 .extendedQuery,
                 .ping,
                 .commit,
                 .rollback,
                 .renegotiatingTLS:
                self.taskQueue.append(task)
                return .wait

            case .readyForQuery:
                return self.executeTask(task)

            case .readyToLogOff, .loggingOff, .closing, .closed:
                oracleError = .clientClosesConnection(underlying: nil)
            
            case .modifying:
                preconditionFailure("invalid state")
            }
        }

        switch task {
        case .extendedQuery(let queryContext):
            switch queryContext.statement {
            case .ddl(let promise),
                .dml(let promise),
                .plsql(let promise),
                .query(let promise):
                return .failQuery(
                    promise, with: oracleError, cleanupContext: nil
                )
            }
        case .ping(let promise):
            return .failPing(promise, with: oracleError)
        case .commit(let promise):
            return .failCommit(promise, with: oracleError)
        case .rollback(let promise):
            return .failRollback(promise, with: oracleError)
        }
    }

    mutating func channelReadComplete() -> ConnectionAction {
        switch self.state {
        case .initialized,
             .connectMessageSent,
             .protocolMessageSent,
             .dataTypesMessageSent,
             .waitingToStartAuthentication,
             .authenticating,
             .readyForQuery,
             .ping,
             .commit,
             .rollback,
             .readyToLogOff,
             .loggingOff,
             .closing,
             .closed,
             .renegotiatingTLS:
            return .wait

        case .extendedQuery(var extendedQuery):
            self.state = .modifying // avoid CoW
            let action = extendedQuery.channelReadComplete()
            self.state = .extendedQuery(extendedQuery)
            return self.modify(with: action)

        case .modifying:
            preconditionFailure("Invalid state")
        }
    }

    mutating func readEventCaught() -> ConnectionAction {
        switch self.state {
        case .initialized:
            preconditionFailure(
                "Received a read event on a connection that was never opened"
            )

        case .extendedQuery(var extendedQuery):
            return self.avoidingStateMachineCoW { machine in
                let action = extendedQuery.readEventCaught()
                machine.state = .extendedQuery(extendedQuery)
                return machine.modify(with: action)
            }

        case .modifying:
            preconditionFailure("Invalid state")

        default:
            return .read
        }
    }

    mutating func acceptReceived(
        _ accept: OracleBackendMessage.Accept, description: Description
    ) -> ConnectionAction {
        guard case .connectMessageSent = state else {
            preconditionFailure()
        }

        let capabilities = accept.newCapabilities

        if capabilities.protocolVersion < Constants.TNS_VERSION_MIN_ACCEPTED {
            return self.errorHappened(.serverVersionNotSupported)
        }

        if
            capabilities.supportsOOB && capabilities.protocolVersion >=
            Constants.TNS_VERSION_MIN_OOB_CHECK
        {
            // TODO: Perform OOB Check
            // send OUT_OF_BAND + reset marker message through socket
        }

        // Starting in 23c, a cookie can be sent along with the protocol, data
        // types and authorization messages without waiting for the server to
        // respond to each of the messages in turn
        if let dbUUID = accept.dbCookieUUID, let cookie = ConnectionCookieManager.shared.get(by: dbUUID, description: description) {
            self.state = .waitingToStartAuthentication
            return .provideAuthenticationContext(cookie)
        }

        self.state = .protocolMessageSent
        return .sendProtocol
    }

    mutating func protocolReceived() -> ConnectionAction {
        guard case .protocolMessageSent = state else {
            preconditionFailure()
        }
        self.state = .dataTypesMessageSent
        return .sendDataTypes
    }

    func resendReceived() -> ConnectionAction {
        switch self.state {
        case .initialized:
            preconditionFailure(
                "How can we resend anything to a connection that was never opened"
            )
        case .connectMessageSent:
            return .sendConnect
        case .protocolMessageSent:
            return .sendProtocol
        case .dataTypesMessageSent:
            return .sendDataTypes
        case .waitingToStartAuthentication:
            return .wait
        case .authenticating:
            fatalError("Does this even happen?")
        case .readyForQuery:
            return .wait
        case .extendedQuery:
            fatalError("Does this even happen?")
        case .ping:
            return .sendPing
        case .commit:
            return .sendCommit
        case .rollback:
            return .sendRollback
        case .readyToLogOff:
            return .wait
        case .loggingOff(let promise):
            return .logoffConnection(promise)
        case .renegotiatingTLS:
            fatalError("Does this even happen?")

        case .closing, .closed:
            preconditionFailure(
                "How can we resend anything, if the connection is closed"
            )

        case .modifying:
            preconditionFailure("Invalid state")
        }
    }

    mutating func dataTypesReceived() -> ConnectionAction {
        guard case .dataTypesMessageSent = state else {
            preconditionFailure()
        }
        self.state = .waitingToStartAuthentication
        return .provideAuthenticationContext(nil)
    }

    mutating func parameterReceived(
        parameters: OracleBackendMessage.Parameter
    ) -> ConnectionAction {
        switch self.state {
        case .initialized,
             .connectMessageSent,
             .protocolMessageSent,
             .dataTypesMessageSent,
             .waitingToStartAuthentication,
             .renegotiatingTLS:
            preconditionFailure()

        case .authenticating(var authState):
            return self.avoidingStateMachineCoW { machine in
                let action = authState.parameterReceived(parameters: parameters)
                machine.state = .authenticating(authState)
                return machine.modify(with: action)
            }

        case .readyForQuery, .extendedQuery, .ping, .commit, .rollback:
            fatalError("Is this possible?")

        case .readyToLogOff, .loggingOff, .closing, .closed, .modifying:
            preconditionFailure()
        }
    }

    mutating func markerReceived() -> ConnectionAction {
        switch self.state {
        case .initialized, 
             .waitingToStartAuthentication,
             .readyForQuery,
             .readyToLogOff,
             .closed,
             .renegotiatingTLS:
            preconditionFailure()
        case .connectMessageSent,
             .protocolMessageSent,
             .dataTypesMessageSent,
             .authenticating,
             .extendedQuery,
             .ping,
             .commit,
             .rollback:
            switch self.markerState {
            case .noMarkerSent:
                self.markerState = .markerSent
                return .sendMarker
            case .markerSent:
                // A marker has already been sent, don't send another one,
                // because this would cancel the current operation.
                self.markerState = .noMarkerSent
                return .wait
            }
        case .loggingOff, .closing:
            return self.errorHappened(.unexpectedBackendMessage(.marker))

        case .modifying:
            preconditionFailure("invalid state")
        }
    }

    mutating func statusReceived(
        _ status: OracleBackendMessage.Status
    ) -> ConnectionAction {
        switch self.state {
        case .initialized:
            preconditionFailure()
        
        case .connectMessageSent,
             .protocolMessageSent,
             .dataTypesMessageSent,
             .waitingToStartAuthentication,
             .authenticating,
             .readyForQuery,
             .extendedQuery,
             .renegotiatingTLS:
            return self.errorHappened(
                .unexpectedBackendMessage(.status(status))
            )

        case .ping(let promise):
            return .succeedPing(promise)

        case .commit(let promise):
            return .succeedCommit(promise)
            
        case .rollback(let promise):
            return .succeedRollback(promise)

        case .readyToLogOff:
            preconditionFailure()

        case .loggingOff(let promise):
            self.state = .closing
            return .closeConnection(promise)

        case .closing:
            return .wait
        case .closed:
            preconditionFailure()

        case .modifying:
            preconditionFailure("invalid state")
        }
    }

    mutating func describeInfoReceived(
        _ describeInfo: DescribeInfo
    ) -> ConnectionAction {
        switch self.state {
        case .extendedQuery(var queryState):
            return self.avoidingStateMachineCoW { machine in
                let action = queryState.describeInfoReceived(describeInfo)
                machine.state = .extendedQuery(queryState)
                return machine.modify(with: action)
            }
        default:
            return self.closeConnectionAndCleanup(
                .unexpectedBackendMessage(.describeInfo(describeInfo))
            )
        }
    }

    mutating func rowHeaderReceived(
        _ rowHeader: OracleBackendMessage.RowHeader
    ) -> ConnectionAction {
        switch self.state {
        case .extendedQuery(var queryState):
            return self.avoidingStateMachineCoW { machine in
                let action = queryState.rowHeaderReceived(rowHeader)
                machine.state = .extendedQuery(queryState)
                return machine.modify(with: action)
            }
        default:
            return self.closeConnectionAndCleanup(
                .unexpectedBackendMessage(.rowHeader(rowHeader))
            )
        }
    }

    mutating func rowDataReceived(
        _ rowData: OracleBackendMessage.RowData,
        capabilities: Capabilities
    ) -> ConnectionAction {
        switch self.state {
        case .extendedQuery(var queryState):
            return self.avoidingStateMachineCoW { machine in
                let action = queryState.rowDataReceived(
                    rowData, capabilities: capabilities
                )
                machine.state = .extendedQuery(queryState)
                return machine.modify(with: action)
            }
        default:
            return self.closeConnectionAndCleanup(
                .unexpectedBackendMessage(.rowData(rowData))
            )
        }
    }

    mutating func queryParameterReceived(
        _ parameter: OracleBackendMessage.QueryParameter
    ) -> ConnectionAction {
        return .wait
    }

    mutating func bitVectorReceived(
        _ bitVector: OracleBackendMessage.BitVector
    ) -> ConnectionAction{
        switch self.state {
        case .extendedQuery(var queryState):
            return self.avoidingStateMachineCoW { machine in
                let action = queryState.bitVectorReceived(bitVector)
                machine.state = .extendedQuery(queryState)
                return machine.modify(with: action)
            }
        default:
            preconditionFailure()
        }
    }

    mutating func backendErrorReceived(
        _ error: OracleBackendMessage.BackendError
    ) -> ConnectionAction {
        switch self.state {
        case .extendedQuery(var queryState):
            return self.avoidingStateMachineCoW { machine in
                let action = queryState.errorReceived(error)
                machine.state = .extendedQuery(queryState)
                return machine.modify(with: action)
            }
        case .authenticating(var authState):
            return self.avoidingStateMachineCoW { machine in
                let action = authState.errorReceived(error)
                machine.state = .authenticating(authState)
                return machine.modify(with: action)
            }
        default:
            fatalError()
        }
    }

    mutating func cancelQueryStream() -> ConnectionAction {
        guard case .extendedQuery(var queryState) = state else {
            preconditionFailure("Tried to cancel stream without active query")
        }

        return self.avoidingStateMachineCoW { machine in
            let action = queryState.cancel()
            machine.state = .extendedQuery(queryState)
            return machine.modify(with: action)
        }

    }

    mutating func requestQueryRows() -> ConnectionAction {
        guard case .extendedQuery(var queryState) = state else {
            preconditionFailure(
                "Tried to consume next row, without active query"
            )
        }

        return self.avoidingStateMachineCoW { machine in
            let action = queryState.requestQueryRows()
            machine.state = .extendedQuery(queryState)
            return machine.modify(with: action)
        }
    }

    mutating func readyForQueryReceived() -> ConnectionAction {
        switch self.state {
        case .extendedQuery(let extendedQuery):
            guard extendedQuery.isComplete else { preconditionFailure() }

            self.state = .readyForQuery
            return self.executeNextQueryFromQueue()
        case .ping, .commit, .rollback:
            self.state = .readyForQuery
            return self.executeNextQueryFromQueue()
        default:
            preconditionFailure()
        }
    }

    mutating func chunkReceived(
        _ buffer: ByteBuffer, capabilities: Capabilities
    ) -> ConnectionAction {
        switch self.state {
        case .extendedQuery(var queryState):
            return self.avoidingStateMachineCoW { machine in
                let action = queryState.chunkReceived(
                    buffer, capabilities: capabilities
                )
                machine.state = .extendedQuery(queryState)
                return machine.modify(with: action)
            }

        default:
            preconditionFailure()
        }
    }

    mutating func ioVectorReceived(
        _ vector: OracleBackendMessage.InOutVector
    ) -> ConnectionAction {
        guard case var .extendedQuery(queryState) = self.state else {
            preconditionFailure()
        }

        return self.avoidingStateMachineCoW { machine in
            let action = queryState.ioVectorReceived(vector)
            machine.state = .extendedQuery(queryState)
            return machine.modify(with: action)
        }
    }

    mutating func renegotiatingTLS() {
        self.state = .renegotiatingTLS
    }

    mutating func tlsEstablished() -> ConnectionAction {
        guard case .renegotiatingTLS = self.state else {
            return .wait
        }
        self.state = .connectMessageSent
        return .sendConnect
    }

    // MARK: - Private Methods -

    private mutating func startAuthentication(
        _ authContext: AuthContext, cookie: ConnectionCookie?
    ) -> ConnectionAction {
        guard case .waitingToStartAuthentication = state else {
            preconditionFailure(
                "Can only start authentication after connection is established"
            )
        }

        return self.avoidingStateMachineCoW { machine in
            var authState = AuthenticationStateMachine(
                authContext: authContext, cookie: cookie
            )
            let action = authState.start()
            machine.state = .authenticating(authState)
            return machine.modify(with: action)
        }
    }

    private mutating func closeConnectionAndCleanup(
        _ error: OracleSQLError,
        closePromise: EventLoopPromise<Void>? = nil
    ) -> ConnectionAction {
        switch self.state {
        case .initialized,
             .connectMessageSent,
             .protocolMessageSent,
             .dataTypesMessageSent,
             .waitingToStartAuthentication,
             .readyForQuery,
             .ping,
             .commit,
             .rollback,
             .renegotiatingTLS:
            let cleanupContext = self.setErrorAndCreateCleanupContext(
                error, closePromise: closePromise
            )
            return .closeConnectionAndCleanup(cleanupContext)

        case .authenticating(var authState):
            let cleanupContext = self.setErrorAndCreateCleanupContext(
                error, closePromise: closePromise
            )

            if authState.isComplete {
                // in case the auth state machine is complete, all necessary
                // actions have already been forwarded to the consumer. We can
                // close and cleanup without caring about the substate machine.
                return .closeConnectionAndCleanup(cleanupContext)
            }

            let action = authState.errorHappened(error)
            guard case .reportAuthenticationError = action else {
                preconditionFailure("Expect to fail auth")
            }
            return .closeConnectionAndCleanup(cleanupContext)

        case .extendedQuery(var queryState):
            let cleanupContext = self.setErrorAndCreateCleanupContext(
                error, closePromise: closePromise
            )

            if queryState.isComplete {
                // in case the query state machine is complete, all necessary
                // actions have already been forwarded to the consumer. We can
                // close and cleanup without caring about the substate machine.
                return .closeConnectionAndCleanup(cleanupContext)
            }

            switch queryState.errorHappened(error) {
            case .sendExecute,
                .sendReexecute,
                .sendFetch,
                .succeedQuery,
                .needMoreData,
                .forwardRows,
                .forwardStreamComplete,
                .forwardCancelComplete,
                .read,
                .wait:
                preconditionFailure("invalid state")

            case .evaluateErrorAtConnectionLevel:
                return .closeConnectionAndCleanup(cleanupContext)

            case .failQuery(let promise, with: let error):
                return .failQuery(
                    promise, with: error, cleanupContext: cleanupContext
                )

            case .forwardStreamError(
                let error, let read, let cursorID, let clientCancelled
            ):
                return .forwardStreamError(
                    error,
                    read: read,
                    cursorID: cursorID,
                    clientCancelled: clientCancelled
                )
            }

        case .readyToLogOff:
            self.state = .loggingOff(closePromise)
            return .logoffConnection(closePromise)

        case .loggingOff, .closing, .closed:
            // We might run into this case because of reentrancy. For example:
            // After we received an backend unexpected message, that we read
            // of the wire, we bring this connection into the error state and
            // will try to close the connection. However the server might have
            // sent further follow up messages. In those cases we will run into
            // this method again and again. We should just ignore those events.
            return .wait

        case .modifying:
            preconditionFailure("Invalid state")
        }
    }

    private mutating func executeNextQueryFromQueue() -> ConnectionAction {
        guard case .readyForQuery = state else {
            preconditionFailure(
                "Only expected to be invoked, if we are readyForQuery"
            )
        }

        if let task = self.taskQueue.popFirst() {
            return self.executeTask(task)
        }

        // if we don't have anything left to do and we are quiescing,
        // we should close
        if case .quiescing(let closePromise) = self.quiescingState {
            self.state = .closing
            return .closeConnection(closePromise)
        }

        return .fireEventReadyForQuery
    }

    private mutating func executeTask(_ task: OracleTask) -> ConnectionAction {
        guard case .readyForQuery = state else {
            preconditionFailure(
                "Only expected to be invoked, if we are readyToQuery"
            )
        }

        switch task {
        case .extendedQuery(let queryContext):
            return self.avoidingStateMachineCoW { machine in
                var extendedQuery = ExtendedQueryStateMachine(
                    queryContext: queryContext
                )
                let action = extendedQuery.start()
                machine.state = .extendedQuery(extendedQuery)
                return machine.modify(with: action)
            }
        case .ping(let promise):
            return self.avoidingStateMachineCoW { machine in
                machine.state = .ping(promise)
                return .sendPing
            }
        case .commit(let promise):
            return self.avoidingStateMachineCoW { machine in
                machine.state = .commit(promise)
                return .sendCommit
            }
        case .rollback(let promise):
            return self.avoidingStateMachineCoW { machine in
                machine.state = .rollback(promise)
                return .sendRollback
            }
        }
    }
}

extension ConnectionStateMachine {

    func shouldCloseConnection(reason error: OracleSQLError) -> Bool {
        switch error.code.base {
        case .failedToAddSSLHandler,
             .failedToVerifyTLSCertificates,
             .connectionError,
             .messageDecodingFailure,
             .missingParameter,
             .unexpectedBackendMessage,
             .serverVersionNotSupported,
             .sidNotSupported,
             .uncleanShutdown:
            return true
        case .queryCancelled, .nationalCharsetNotSupported, .malformedQuery:
            return false
        case .server:
            switch error.serverInfo?.number {
            case 28, 600: // connection closed
                return true
            default:
                return false
            }
        case .clientClosesConnection, .clientClosedConnection:
            preconditionFailure(
                "Pure client error, that is thrown directly from OracleConnection"
            )
        }
    }

    mutating func setErrorAndCreateCleanupContextIfNeeded(
        _ error: OracleSQLError
    ) -> ConnectionAction.CleanUpContext? {
        guard self.shouldCloseConnection(reason: error) else { return nil }
        return self.setErrorAndCreateCleanupContext(error)
    }

    mutating func setErrorAndCreateCleanupContext(
        _ error: OracleSQLError, closePromise: EventLoopPromise<Void>? = nil
    ) -> ConnectionAction.CleanUpContext {
        let tasks = Array(self.taskQueue)
        self.taskQueue.removeAll()

        var forwardedPromise: EventLoopPromise<Void>? = nil
        if
            case .quiescing(.some(let quiescePromise)) = self.quiescingState,
            let closePromise
        {
            quiescePromise.futureResult.cascade(to: closePromise)
            forwardedPromise = quiescePromise
        } else if
            case .quiescing(.some(let quiescePromise)) = self.quiescingState
        {
            forwardedPromise = quiescePromise
        } else {
            forwardedPromise = closePromise
        }

        self.state = .readyToLogOff

        var action = ConnectionAction.CleanUpContext.Action.close
        if case .uncleanShutdown = error.code.base {
            action = .fireChannelInactive
        }

        return .init(
            action: action,
            tasks: tasks,
            error: error,
            closePromise: forwardedPromise
        )
    }
}

extension ConnectionStateMachine {
    /// While the state machine logic above is great, there is a downside to having all of the state machine
    /// data in associated data on enumerations: any modification of that data will trigger copy on write
    /// for heap-allocated data. That means that for _every operation on the state machine_ we will CoW
    /// our underlying state, which is not good.
    ///
    /// The way we can avoid this is by using this helper function. It will temporarily set state to a value with
    /// no associated data, before attempting the body of the function. It will also verify that the state
    /// machine never remains in this bad state.
    ///
    /// A key note here is that all callers must ensure that they return to a good state before they exit.
    ///
    /// Sadly, because it's generic and has a closure, we need to force it to be inlined at all call sites,
    /// which is not idea.
    @inline(__always)
    private mutating func avoidingStateMachineCoW<ReturnType>(
        _ body: (inout ConnectionStateMachine) -> ReturnType
    ) -> ReturnType {
        self.state = .modifying
        defer {
            assert(!self.isModifying)
        }

        return body(&self)
    }

    private var isModifying: Bool {
        if case .modifying = self.state {
            return true
        } else {
            return false
        }
    }
}

extension ConnectionStateMachine {
    mutating func modify(
        with action: AuthenticationStateMachine.Action
    ) -> ConnectionAction {
        switch action {
        case .sendAuthenticationPhaseOne(let authContext, let cookie):
            return .sendAuthenticationPhaseOne(authContext, cookie)
        case .sendAuthenticationPhaseTwo(let authContext, let parameters):
            return .sendAuthenticationPhaseTwo(authContext, parameters)
        case .wait:
            return .wait
        case .authenticated(let parameters):
            self.state = .readyForQuery
            return .authenticated(parameters)
        case .reportAuthenticationError(let error):
            let cleanupContext = self.setErrorAndCreateCleanupContext(error)
            return .closeConnectionAndCleanup(cleanupContext)
        }
    }
}

extension ConnectionStateMachine {
    mutating func modify(
        with action: ExtendedQueryStateMachine.Action
    ) -> ConnectionAction {
        switch action {
        case .sendExecute(let context, let describeInfo):
            return .sendExecute(context, describeInfo)
        case .sendReexecute(let queryContext, let cleanupContext):
            return .sendReexecute(queryContext, cleanupContext)
        case .sendFetch(let context):
            return .sendFetch(context)
        case .failQuery(let promise, let error):
            return .failQuery(promise, with: error, cleanupContext: nil)
        case .succeedQuery(let promise, let columns):
            return .succeedQuery(promise, columns)
        case .needMoreData:
            return .needMoreData
        case .forwardRows(let rows):
            return .forwardRows(rows)
        case .forwardStreamComplete(let rows, let cursorID):
            return .forwardStreamComplete(rows, cursorID: cursorID)
        case .forwardStreamError(
            let error, let read, let cursorID, let clientCancelled
        ):
            return .forwardStreamError(
                error, 
                read: read,
                cursorID: cursorID,
                clientCancelled: clientCancelled
            )
        case .forwardCancelComplete:
            return .fireEventReadyForQuery
        case .evaluateErrorAtConnectionLevel(let error):
            if let cleanupContext = 
                self.setErrorAndCreateCleanupContextIfNeeded(error)
            {
                return .closeConnectionAndCleanup(cleanupContext)
            }
            return .wait
        case .read:
            return .read
        case .wait:
            return .wait
        }
    }
}

struct AuthContext: Equatable {
    var method: OracleAuthenticationMethod
    var service: OracleServiceMethod

    var terminalName: String
    var programName: String
    var machineName: String
    var pid: Int32
    var processUsername: String

    var proxyUser: String?
    var jdwpData: String?
    var peerAddress: SocketAddress?
    var customTimezone: TimeZone?

    var mode: AuthenticationMode
    var description: Description

    var debugDescription: String {
        """
        AuthContext(method: \(String(reflecting: self.method)), \
        service: \(String(reflecting: self.service)), \
        terminalName: \(String(reflecting: self.terminalName)), \
        programName: \(String(reflecting: self.programName)), \
        machineName: \(String(reflecting: self.machineName)), \
        pid: \(String(reflecting: self.pid)), \
        processUsername: \(String(reflecting: self.processUsername)), \
        proxyUser: \(String(reflecting: self.proxyUser)), \
        jdwpData: \(self.jdwpData != nil ? "********" : "nil")), \
        peerAddress: \(String(reflecting: self.peerAddress)), \
        customTimezone: \(String(reflecting: self.customTimezone)), \
        mode: \(String(reflecting: self.mode)), \
        description: \(String(reflecting: self.description)))
        """
    }
}
