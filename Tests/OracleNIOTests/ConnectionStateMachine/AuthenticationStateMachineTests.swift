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

#if compiler(>=6.0)
import Testing

@testable import OracleNIO

@Suite struct AuthenticationStateMachineTests {
    @Test func fastAuthHappyPath() {
        var capabilities = Capabilities()
        capabilities.supportsFastAuth = true
        capabilities.protocolVersion = Constants.TNS_VERSION_DESIRED
        let accept = OracleBackendMessage.Accept(newCapabilities: capabilities)
        let description = Description(
            connectionID: "1",
            addressLists: [],
            service: .serviceName("service_name"),
            sslServerDnMatch: false,
            purity: .default
        )
        let authContext = AuthContext(
            method: .init(username: "test", password: "pasword123"),
            service: .serviceName("service_name"),
            terminalName: "",
            programName: "",
            machineName: "",
            pid: 1,
            processUsername: "",
            mode: .default,
            description: description
        )

        var state = ConnectionStateMachine()

        #expect(state.connected() == .sendConnect)
        #expect(state.acceptReceived(accept, description: description) == .provideAuthenticationContext(.allowed))
        #expect(state.provideAuthenticationContext(authContext, fastAuth: .allowed) == .sendFastAuth(authContext))
        #expect(state.protocolReceived() == .wait)
        #expect(state.dataTypesReceived() == .wait)
        #expect(state.parameterReceived(parameters: .init([:])) == .sendAuthenticationPhaseTwo(authContext, .init([:])))
        #expect(state.parameterReceived(parameters: [:]) == .authenticated([:]))
    }

    @Test func authHappyPath() {
        var capabilities = Capabilities()
        capabilities.protocolVersion = Constants.TNS_VERSION_DESIRED
        let accept = OracleBackendMessage.Accept(newCapabilities: capabilities)
        let description = Description(
            connectionID: "1",
            addressLists: [],
            service: .serviceName("service_name"),
            sslServerDnMatch: false,
            purity: .default
        )
        let authContext = AuthContext(
            method: .init(username: "test", password: "pasword123"),
            service: .serviceName("service_name"),
            terminalName: "",
            programName: "",
            machineName: "",
            pid: 1,
            processUsername: "",
            mode: .default,
            description: description
        )

        var state = ConnectionStateMachine()

        #expect(state.connected() == .sendConnect)
        #expect(state.acceptReceived(accept, description: description) == .sendProtocol)
        #expect(state.protocolReceived() == .sendDataTypes)
        #expect(state.dataTypesReceived() == .provideAuthenticationContext(.denied))
        #expect(
            state.provideAuthenticationContext(authContext, fastAuth: .denied) ==
            .sendAuthenticationPhaseOne(authContext)
        )
        #expect(
            state.parameterReceived(parameters: .init([:])) ==
            .sendAuthenticationPhaseTwo(authContext, .init([:])))
        #expect(state.parameterReceived(parameters: [:]) == .authenticated([:]))
    }
}
#endif
