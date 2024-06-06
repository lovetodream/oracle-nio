import XCTest
import NIOCore
@testable import OracleNIO

final class CapabilitiesTests: XCTestCase {
    func testEndOfRequestSupport() {
        var capabilities = Capabilities()
        XCTAssertFalse(capabilities.supportsEndOfRequest)
        capabilities.adjustForProtocol(
            version: UInt16(Constants.TNS_VERSION_MIN_END_OF_RESPONSE),
            options: 0, flags: Constants.TNS_ACCEPT_FLAG_HAS_END_OF_REQUEST
        )
        XCTAssertTrue(capabilities.supportsEndOfRequest)
        var serverCaps = ByteBuffer(repeating: 0, count: Constants.TNS_CCAP_MAX)
        serverCaps.setInteger(
            UInt8(Constants.TNS_CCAP_FIELD_VERSION_19_1),
            at: Constants.TNS_CCAP_FIELD_VERSION
        )
        capabilities.adjustForServerCompileCapabilities(serverCaps)
        XCTAssertFalse(capabilities.supportsEndOfRequest)
    }
}
