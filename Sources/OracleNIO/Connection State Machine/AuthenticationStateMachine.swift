// Copyright 2024 Timo Zacherl
// SPDX-License-Identifier: Apache-2.0

import NIOCore

struct AuthenticationStateMachine {

    enum State {
        case initialized
        case authenticationPhaseOneSent
        case authenticationPhaseTwoSent

        case error(OracleSQLError)
        case authenticated
    }

    enum Action {
        case sendAuthenticationPhaseOne(AuthContext, ConnectionCookie?)
        case sendAuthenticationPhaseTwo(
            AuthContext,
            OracleBackendMessage.Parameter
        )
        case wait
        case authenticated(OracleBackendMessage.Parameter)

        case reportAuthenticationError(OracleSQLError)
    }

    let authContext: AuthContext
    let cookie: ConnectionCookie?
    var state: State

    init(authContext: AuthContext, cookie: ConnectionCookie?) {
        self.authContext = authContext
        self.cookie = cookie
        self.state = .initialized
    }

    mutating func start() -> Action {
        guard case .initialized = state else {
            preconditionFailure("Unexpected state")
        }
        self.state = .authenticationPhaseOneSent
        return .sendAuthenticationPhaseOne(self.authContext, self.cookie)
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

    mutating func errorReceived(_ message: OracleBackendMessage.BackendError) -> Action {
        return self.setAndFireError(.server(message))
    }

    mutating func errorHappened(_ error: OracleSQLError) -> Action {
        return self.setAndFireError(error)
    }

    private mutating func setAndFireError(_ error: OracleSQLError) -> Action {
        switch self.state {
        case .initialized:
            preconditionFailure("This doesn't make any sense")
        case .authenticationPhaseOneSent,
                .authenticationPhaseTwoSent:
            self.state = .error(error)
            return .reportAuthenticationError(error)
        case .authenticated, .error:
            preconditionFailure("This state must not be reached")
        }
    }

    var isComplete: Bool {
        switch self.state {
        case .authenticated, .error:
            return true
        case .initialized,
            .authenticationPhaseOneSent,
            .authenticationPhaseTwoSent:
            return false
        }
    }
}
