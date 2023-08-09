import NIOCore

struct ConnectionStateMachine {
    enum State {
        case initialized
        case connectMessageSent
        case protocolMessageSent
        case dataTypesMessageSent
        case waitingToStartAuthentication
        case authenticating(AuthenticationStateMachine)
        case readyForQuery
        case error
        case loggingOff(EventLoopPromise<Void>?)
        case closing
        case closed

        case modifying
    }

    enum QuiescingState {
        case notQuiescing
        case quiescing(closePromise: EventLoopPromise<Void>?)
    }

    enum ConnectionAction {
        case read
        case wait
        case logoffConnection(EventLoopPromise<Void>?)
        case closeConnection(EventLoopPromise<Void>?)
        case fireChannelInactive

        // Connection Establishment Actions
        case sendConnect
        case sendProtocol
        case sendDataTypes

        // Authentication Actions
        case provideAuthenticationContext
        case sendAuthenticationPhaseOne(AuthContext)
        case sendAuthenticationPhaseTwo(
            AuthContext, OracleBackendMessage.Parameter
        )
        case authenticated(OracleBackendMessage.Parameter)

        case sendMarker
    }

    private var state: State
    private var taskQueue = CircularBuffer<OracleTask>()
    private var quiescingState: QuiescingState = .notQuiescing

    init() {
        self.state = .initialized
    }

    mutating func connected() -> ConnectionAction {
        switch self.state {
        case .initialized:
            self.state = .connectMessageSent
            return .sendConnect
        case .connectMessageSent,
            .protocolMessageSent,
            .dataTypesMessageSent,
            .waitingToStartAuthentication,
            .authenticating,
            .readyForQuery,
            .error,
            .loggingOff,
            .closing,
            .closed,
            .modifying:
            return .wait
        }
    }

    mutating func provideAuthenticationContext(
        _ authContext: AuthContext
    ) -> ConnectionAction {
        self.startAuthentication(authContext)
    }

    mutating func close(
        _ promise: EventLoopPromise<Void>?
    ) -> ConnectionAction {
        switch self.state {
        case .closing, .closed, .error:
            // we are already closed, but sometimes an upstream handler might
            // want to close the connection, though it has already been closed
            // by the remote. Typical race condition.
            return .closeConnection(promise)
        case .readyForQuery:
            precondition(self.taskQueue.isEmpty, """
            The State should only be .readyForQuery if there are no more tasks \
            in the queue
            """)
            self.state = .loggingOff(promise)
            return .logoffConnection(promise)
        case .loggingOff(let promise):
            self.state = .closing
            return .closeConnection(promise)
        default:
            switch self.quiescingState {
            case .notQuiescing:
                self.quiescingState = .quiescing(closePromise: promise)
            case .quiescing(.some(let closePromise)):
                closePromise.futureResult.cascade(to: promise)
            case .quiescing(.none):
                self.quiescingState = .quiescing(closePromise: promise)
            }
            return .wait
        }
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
            .readyForQuery:
            return self.errorHappened(.uncleanShutdown)
        case .error, .loggingOff, .closing:
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
            .authenticating,
            .dataTypesMessageSent,
            .protocolMessageSent,
            .waitingToStartAuthentication,
            .initialized,
            .readyForQuery,
            .loggingOff:
            // TODO: handle errors
            fatalError()
        case .error:
            return .wait
        case .closing:
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
        // check if we are quiescing, if so fail task immediately
        if case .quiescing = self.quiescingState {
            // TODO: fail
            fatalError()
        }

        switch self.state {
        case .closed:
            // TODO: fail
            fatalError()
        default:
            self.taskQueue.append(task)
            return .wait
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
            .error,
            .loggingOff,
            .closing,
            .closed:
            return .wait

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
        case .connectMessageSent:
            return .read
        case .protocolMessageSent:
            return .read
        case .dataTypesMessageSent:
            return .read
        case .waitingToStartAuthentication:
            return .read
        case .authenticating:
            return .read
        case .readyForQuery:
            return .read
        case .error:
            return .read
        case .loggingOff:
            return .read
        case .closing:
            return .read
        case .closed:
            preconditionFailure(
                "How can we receive a read, if the connection is closed"
            )

        case .modifying:
            preconditionFailure("Invalid state")
        }
    }

    mutating func acceptReceived() -> ConnectionAction {
        guard case .connectMessageSent = state else {
            // TODO: any other cases?
            fatalError()
        }
        self.state = .protocolMessageSent
        return .sendProtocol
    }

    mutating func protocolReceived() -> ConnectionAction {
        guard case .protocolMessageSent = state else {
            fatalError()
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
            fatalError()
        case .dataTypesMessageSent:
            fatalError()
        case .waitingToStartAuthentication:
            fatalError()
        case .authenticating:
            fatalError()
        case .readyForQuery:
            fatalError()
        case .error:
            fatalError()
        case .loggingOff:
            fatalError()
        case .closing:
            fatalError()
        case .closed:
            preconditionFailure(
                "How can we resend anything, if the connection is closed"
            )

        case .modifying:
            preconditionFailure("Invalid state")
        }
    }

    mutating func dataTypesReceived() -> ConnectionAction {
        guard case .dataTypesMessageSent = state else {
            fatalError()
        }
        self.state = .waitingToStartAuthentication
        return .provideAuthenticationContext
    }

    mutating func parameterReceived(
        parameters: OracleBackendMessage.Parameter
    ) -> ConnectionAction {
        switch self.state {
        case .initialized,
            .connectMessageSent,
            .protocolMessageSent,
            .dataTypesMessageSent,
            .waitingToStartAuthentication:
            preconditionFailure()

        case .authenticating(var authState):
            return self.avoidingStateMachineCoW { machine in
                let action = authState.parameterReceived(parameters: parameters)
                machine.state = .authenticating(authState)
                return machine.modify(with: action)
            }

        case .readyForQuery:
            fatalError()

        case .error, .loggingOff, .closing, .closed, .modifying:
            preconditionFailure()
        }
    }

    mutating func markerReceived() -> ConnectionAction {
        switch self.state {
        case .initialized, .waitingToStartAuthentication, .readyForQuery, .closed:
            preconditionFailure()
        case .connectMessageSent, .protocolMessageSent, .dataTypesMessageSent, .authenticating:
            return .sendMarker
        case .error:
            fatalError()
        case .loggingOff:
            fatalError()
        case .closing:
            fatalError()

        case .modifying:
            preconditionFailure("invalid state")
        }
    }

    mutating func statusReceived() -> ConnectionAction {
        switch self.state {
        case .initialized:
            preconditionFailure()
        case .connectMessageSent:
            fatalError()
        case .protocolMessageSent:
            fatalError()
        case .dataTypesMessageSent:
            fatalError()
        case .waitingToStartAuthentication:
            fatalError()
        case .authenticating(_):
            fatalError()
        case .readyForQuery:
            fatalError()
        case .error:
            fatalError()
        case .loggingOff(let promise):
            self.state = .closing
            return .closeConnection(promise)
        case .closing:
            fatalError()
        case .closed:
            preconditionFailure()

        case .modifying:
            preconditionFailure("invalid state")
        }
    }

    // MARK: - Private Methods -

    private mutating func startAuthentication(_ authContext: AuthContext) -> ConnectionAction {
        guard case .waitingToStartAuthentication = state else {
            preconditionFailure(
                "Can only start authentication after connection is established"
            )
        }

        return self.avoidingStateMachineCoW { machine in
            var authState = AuthenticationStateMachine(authContext: authContext)
            let action = authState.start()
            machine.state = .authenticating(authState)
            return machine.modify(with: action)
        }
    }

    private mutating func closeConnectionAndCleanup(
        _ error: OracleSQLError
    ) -> ConnectionAction {
        switch self.state {
        case .initialized,
            .connectMessageSent,
            .protocolMessageSent,
            .dataTypesMessageSent,
            .waitingToStartAuthentication,
            .authenticating,
            .readyForQuery:
            // TODO: handle cases
            fatalError()
        case .error, .loggingOff, .closing, .closed:
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
        case .sendAuthenticationPhaseOne(let authContext):
            return .sendAuthenticationPhaseOne(authContext)
        case .sendAuthenticationPhaseTwo(let authContext, let parameters):
            return .sendAuthenticationPhaseTwo(authContext, parameters)
        case .wait:
            return .wait
        case .authenticated(let parameters):
            self.state = .readyForQuery
            return .authenticated(parameters)
        case .reportAuthenticationError:
            // TODO: handle error
            fatalError()
        }
    }
}

struct AuthContext: Equatable, CustomDebugStringConvertible {
    var username: String
    var password: String
    var newPassword: String?

    // TODO: document what mode does
    var mode: UInt32 = 0

    var description: Description

    struct Description: Equatable {
        var purity: Purity = .default
        var serviceName: String
    }

    var debugDescription: String {
        """
        AuthContext(username: \(String(reflecting: self.username)), \
        password: ********, \
        newPassword: \(self.newPassword != nil ? "********" : "nil"), \
        mode: \(String(reflecting: self.mode)), \
        description: \(String(reflecting: self.description)))
        """
    }
}
