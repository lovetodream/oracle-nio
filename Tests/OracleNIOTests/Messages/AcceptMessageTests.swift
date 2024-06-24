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
import NIOTestUtils
import XCTest

@testable import OracleNIO

final class AcceptMessageTests: XCTestCase {
    typealias Message = OracleBackendMessageDecoder.Container

    func testDecodeAccept() {
        var expected = [Message]()
        var buffer = ByteBuffer()
        let encoder = OracleBackendMessageEncoder(protocolVersion: 0)

        // add before oob check
        var cap1 = Capabilities()
        cap1.protocolVersion = Constants.TNS_VERSION_MIN_ACCEPTED
        let message1 = Message(messages: [.accept(.init(newCapabilities: cap1))])
        encoder.encode(data: message1, out: &buffer)
        expected.append(message1)

        // add with oob check but without fast auth
        var cap2 = Capabilities()
        cap2.protocolVersion = Constants.TNS_VERSION_MIN_OOB_CHECK
        let message2 = Message(messages: [.accept(.init(newCapabilities: cap2))])
        encoder.encode(data: message2, out: &buffer)
        expected.append(message2)

        // add with oob check and fast auth
        var cap3 = Capabilities()
        cap3.protocolVersion = Constants.TNS_VERSION_MIN_OOB_CHECK
        cap3.supportsFastAuth = true
        let message3 = Message(messages: [.accept(.init(newCapabilities: cap3))])
        encoder.encode(data: message3, out: &buffer)
        expected.append(message3)

        XCTAssertNoThrow(
            try ByteToMessageDecoderVerifier.verifyDecoder(
                inputOutputPairs: [(buffer, expected.map({ [$0] }))],
                decoderFactory: {
                    OracleBackendMessageDecoder()
                }
            ))
    }

    func testDecodeUnsupportedVersion() throws {
        let message = try ByteBuffer(
            bytes: Array(
                hexString:
                    "00 20 00 00 02 00 00 00 01 3a 04 01 20 00 20 00 01 00 00 00 00 20 c5 00 00 00 00 00 00 00 00 00"
                    .replacingOccurrences(of: " ", with: "")
            ))
        XCTAssertThrowsError(
            try ByteToMessageDecoderVerifier.verifyDecoder(inputOutputPairs: [(message, [])]) {
                OracleBackendMessageDecoder()
            },
            expected: OracleSQLError.serverVersionNotSupported
        )
    }
}
