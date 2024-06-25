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
import XCTest

@testable import OracleNIO

final class CapabilitiesTests: XCTestCase {
    func testEndOfRequestSupport() {
        var capabilities = Capabilities()
        XCTAssertFalse(capabilities.supportsEndOfRequest)
        capabilities.adjustForProtocol(
            version: Constants.TNS_VERSION_MIN_END_OF_RESPONSE,
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
