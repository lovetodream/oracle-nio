// Copyright 2024 Timo Zacherl
// SPDX-License-Identifier: Apache-2.0

import XCTest
import NIOCore
import NIOTestUtils
@testable import OracleNIO

final class AcceptMessageTests: XCTestCase {
    typealias Message = OracleBackendMessageDecoder.Container

    func testDecodeAccept() {
        var expected = [Message]()
        var buffer = ByteBuffer()
        let encoder = OracleBackendMessageEncoder(protocolVersion: 0)

        // add before oob check
        let cap1 = Capabilities()
        let message1 = Message(message: .accept(.init(newCapabilities: cap1)))
        encoder.encode(data: message1, out: &buffer)
        expected.append(message1)

        // add with oob check but without fast auth
        var cap2 = Capabilities()
        cap2.protocolVersion = UInt16(Constants.TNS_VERSION_MIN_OOB_CHECK)
        let message2 = Message(message: .accept(.init(newCapabilities: cap2)))
        encoder.encode(data: message2, out: &buffer)
        expected.append(message2)

        // add with oob check and fast auth
        var cap3 = Capabilities()
        cap3.protocolVersion = UInt16(Constants.TNS_VERSION_MIN_OOB_CHECK)
        cap3.supportsFastAuth = true
        let message3 = Message(message: .accept(.init(newCapabilities: cap3)))
        encoder.encode(data: message3, out: &buffer)
        expected.append(message3)

        XCTAssertNoThrow(try ByteToMessageDecoderVerifier.verifyDecoder(
            inputOutputPairs: [(buffer, expected.map({ [$0] }))],
            decoderFactory: {
                OracleBackendMessageDecoder()
            }
        ))
    }
}
