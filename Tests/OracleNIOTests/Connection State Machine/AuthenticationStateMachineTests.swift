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
        XCTAssertEqual(state.acceptReceived(accept, description: description), .provideAuthenticationContext(.allowed))
        XCTAssertEqual(state.provideAuthenticationContext(authContext, fastAuth: .allowed), .sendFastAuth(authContext))
        XCTAssertEqual(state.parameterReceived(parameters: .init([:])), .sendAuthenticationPhaseTwo(authContext, .init([:])))
        XCTAssertEqual(state.parameterReceived(parameters: [:]), .authenticated([:]))
    }
}
