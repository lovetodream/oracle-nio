import NIOCore

struct AuthenticationStateMachine {

    enum State {
        case initialized
        case authenticationPhaseOneSent
        case authenticationPhaseTwoSent

        case error
        case authenticated
    }

    enum Action {
        case sendAuthenticationPhaseOne(AuthContext)
        case sendAuthenticationPhaseTwo(
            AuthContext,
            OracleBackendMessage.Parameter
        )
        case wait
        case authenticated(OracleBackendMessage.Parameter)

        case reportAuthenticationError
    }

    let authContext: AuthContext
    var state: State

    init(authContext: AuthContext) {
        self.authContext = authContext
        self.state = .initialized
    }

    mutating func start() -> Action {
        guard case .initialized = state else {
            preconditionFailure("Unexpected state")
        }
        self.state = .authenticationPhaseOneSent
        return .sendAuthenticationPhaseOne(self.authContext)
    }

    mutating func parameterReceived(
        parameters: OracleBackendMessage.Parameter
    ) -> Action {
        switch self.state {
        case .initialized, .error, .authenticated:
            preconditionFailure()
        case .authenticationPhaseOneSent:
            self.state = .authenticationPhaseTwoSent
            return .sendAuthenticationPhaseTwo(self.authContext, parameters)
        case .authenticationPhaseTwoSent:
            self.state = .authenticated
            return .authenticated(parameters)
        }
    }
}
