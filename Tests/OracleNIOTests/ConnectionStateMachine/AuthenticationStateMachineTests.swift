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

import XCTest

@testable import OracleNIO

final class AuthenticationStateMachineTests: XCTestCase {
    func testFastAuthHappyPath() {
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

        XCTAssertEqual(state.connected(), .sendConnect)
        XCTAssertEqual(
            state.acceptReceived(accept, description: description),
            .provideAuthenticationContext(.allowed))
        XCTAssertEqual(
            state.provideAuthenticationContext(authContext, fastAuth: .allowed),
            .sendFastAuth(authContext))
        XCTAssertEqual(state.protocolReceived(), .wait)
        XCTAssertEqual(state.dataTypesReceived(), .wait)
        XCTAssertEqual(
            state.parameterReceived(parameters: .init([:])),
            .sendAuthenticationPhaseTwo(authContext, .init([:])))
        XCTAssertEqual(state.parameterReceived(parameters: [:]), .authenticated([:]))
    }

    func testAuthHappyPath() {
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

        XCTAssertEqual(state.connected(), .sendConnect)
        XCTAssertEqual(state.acceptReceived(accept, description: description), .sendProtocol)
        XCTAssertEqual(state.protocolReceived(), .sendDataTypes)
        XCTAssertEqual(state.dataTypesReceived(), .provideAuthenticationContext(.denied))
        XCTAssertEqual(
            state.provideAuthenticationContext(authContext, fastAuth: .denied),
            .sendAuthenticationPhaseOne(authContext))
        XCTAssertEqual(
            state.parameterReceived(parameters: .init([:])),
            .sendAuthenticationPhaseTwo(authContext, .init([:])))
        XCTAssertEqual(state.parameterReceived(parameters: [:]), .authenticated([:]))
    }
}
