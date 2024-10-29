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

final class ControlTests: XCTestCase {
    func testResetOOB() throws {
        var message = try ByteBuffer(plainHexEncodedBytes: "00 09")
        let result = try OracleBackendMessage.decode(
            from: &message,
            of: .control,
            context: .init(capabilities: .desired())
        )
        XCTAssertEqual(result.0, [.resetOOB])
    }

    func testUnknown() throws {
        var message = try ByteBuffer(plainHexEncodedBytes: "01 09")
        try XCTAssertThrowsError(
            OracleBackendMessage.decode(
                from: &message,
                of: .control,
                context: .init(capabilities: .desired())
            ), expected: OraclePartialDecodingError.unknownControlTypeReceived(controlType: 0x0109))
    }
}
