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
import Testing

@testable import OracleNIO

@Suite(.timeLimit(.minutes(5))) struct CapabilitiesTests {
    @Test func endOfRequestSupport() {
        var capabilities = Capabilities()
        #expect(capabilities.supportsEndOfRequest == false)
        capabilities.adjustForProtocol(
            version: Constants.TNS_VERSION_MIN_END_OF_RESPONSE,
            options: 0, flags: Constants.TNS_ACCEPT_FLAG_HAS_END_OF_REQUEST
        )
        #expect(capabilities.supportsEndOfRequest)
        var serverCaps = ByteBuffer(repeating: 0, count: Constants.TNS_CCAP_MAX)
        serverCaps.setInteger(
            UInt8(Constants.TNS_CCAP_FIELD_VERSION_19_1),
            at: Constants.TNS_CCAP_FIELD_VERSION
        )
        capabilities.adjustForServerCompileCapabilities(serverCaps)
        #expect(capabilities.supportsEndOfRequest == false)
    }

    @Test("OOB check stays disabled when server omits TNS_ACCEPT_FLAG_CHECK_OOB")
    func oobCheckRequiresServerFlag() {
        var capabilities = Capabilities()
        capabilities.adjustForProtocol(version: 319, options: 0, flags: 0)
        #expect(capabilities.supportsOOBCheck == false)
    }

    @Test("OOB check is enabled only when server advertises TNS_ACCEPT_FLAG_CHECK_OOB")
    func oobCheckEnabledByServerFlag() {
        var capabilities = Capabilities()
        capabilities.adjustForProtocol(
            version: 319, options: 0, flags: Constants.TNS_ACCEPT_FLAG_CHECK_OOB
        )
        #expect(capabilities.supportsOOBCheck)
    }

    @Test("23ai TTC capability bytes match python-oracledb advertisement")
    func ttcCapabilityBytesParity() {
        let capabilities = Capabilities()
        let ttc4 = capabilities.compileCapabilities[Constants.TNS_CCAP_TTC4]
        let ttc5 = capabilities.compileCapabilities[Constants.TNS_CCAP_TTC5]
        let oci3 = capabilities.compileCapabilities[Constants.TNS_CCAP_OCI3]
        let backport2 = capabilities.compileCapabilities[Constants.TNS_CCAP_FEATURE_BACKPORT2]
        let vectorFeatures = capabilities.compileCapabilities[Constants.TNS_CCAP_VECTOR_FEATURES]
        let queueOptions = capabilities.compileCapabilities[Constants.TNS_CCAP_QUEUE_OPTIONS]
        #expect(ttc4 & Constants.TNS_CCAP_TTC4_EXPLICIT_BOUNDARY != 0)
        #expect(ttc5 & Constants.TNS_CCAP_TOKEN_SUPPORTED != 0)
        #expect(ttc5 & Constants.TNS_CCAP_PIPELINING_SUPPORT != 0)
        #expect(oci3 & Constants.TNS_CCAP_OCI3_OCSSYNC != 0)
        #expect(backport2 & Constants.TNS_CCAP_END_USER_SEC_CTX_PIGGYBACK != 0)
        #expect(vectorFeatures & Constants.TNS_CCAP_VECTOR_FEATURE_SPARSE != 0)
        #expect(queueOptions & Constants.TNS_CCAP_DEQUEUE_WITH_SELECTOR != 0)
    }

    @Test("Capabilities round-trip preserves supportsOOBCheck through encode/decode")
    func capabilitiesRoundTrip() throws {
        var original = Capabilities()
        original.adjustForProtocol(
            version: 319, options: 0, flags: Constants.TNS_ACCEPT_FLAG_CHECK_OOB
        )
        var buffer = ByteBuffer()
        try original.encode(into: &buffer)
        let decoded = try Capabilities(from: &buffer)
        #expect(decoded.supportsOOBCheck == original.supportsOOBCheck)
    }
}
