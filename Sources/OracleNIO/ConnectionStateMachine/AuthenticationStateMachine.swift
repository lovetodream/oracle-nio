//===----------------------------------------------------------------------===//
//
// This source file is part of the OracleNIO open source project
//
// Copyright (c) 2024 Timo Zacherl and the OracleNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
// See CONTRIBUTORS.md for the list of OracleNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

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
        case sendFastAuth(AuthContext)
        case sendAuthenticationPhaseOne(AuthContext)
        case sendAuthenticationPhaseTwo(
            AuthContext,
            OracleBackendMessage.Parameter
        )
        case wait
        case authenticated(OracleBackendMessage.Parameter)

        case reportAuthenticationError(OracleSQLError)
    }

    let authContext: AuthContext
    let useFastAuth: Bool
    var comboKey: [UInt8]?
    var state: State

    init(authContext: AuthContext, useFastAuth: Bool) {
        self.authContext = authContext
        self.useFastAuth = useFastAuth
        self.state = .initialized
    }

    mutating func start() -> Action {
        guard case .initialized = self.state else {
            preconditionFailure("Invalid state: \(self.state)")
        }
        self.state = .authenticationPhaseOneSent
        if self.useFastAuth {
            return .sendFastAuth(self.authContext)
        }
        return .sendAuthenticationPhaseOne(self.authContext)
    }

    func protocolReceived() -> Action {
        precondition(self.useFastAuth)
        guard case .authenticationPhaseOneSent = self.state else {
            preconditionFailure("Invalid state: \(self.state)")
        }
        return .wait

    }

    func dataTypesReceived() -> Action {
        precondition(self.useFastAuth)
        guard case .authenticationPhaseOneSent = self.state else {
            preconditionFailure("Invalid state: \(self.state)")
        }
        return .wait
    }

    mutating func parameterReceived(
        parameters: OracleBackendMessage.Parameter
    ) -> Action {
        switch self.state {
        case .initialized, .error, .authenticated:
            preconditionFailure("Invalid state: \(self.state)")
        case .authenticationPhaseOneSent:
            self.state = .authenticationPhaseTwoSent
            return .sendAuthenticationPhaseTwo(self.authContext, parameters)
        case .authenticationPhaseTwoSent:
            if let comboKey {
                let value = parameters["AUTH_SVR_RESPONSE"]
                let validatingPart: ArraySlice<UInt8>?

                if let value, let encodedResponse = try? Array(_hexString: value.value) {
                    let response = try? decryptCBC(comboKey, encodedResponse)
                    if let response, response.count >= 31 {
                        validatingPart = response[16..<32]
                    } else {
                        validatingPart = nil
                    }
                } else {
                    validatingPart = nil
                }
                guard validatingPart == ArraySlice("SERVER_TO_CLIENT".utf8) else {
                    #if OracleBenchmarksEnabled
                        self.state = .authenticated
                        return .authenticated(parameters)
                    #else
                        return self.errorHappened(
                            .connectionError(underlying: OracleSQLError.ConnectionError.invalidServerResponse))
                    #endif
                }
            }

            self.state = .authenticated
            return .authenticated(parameters)
        }
    }

    mutating func errorReceived(_ message: BackendError) -> Action {
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
