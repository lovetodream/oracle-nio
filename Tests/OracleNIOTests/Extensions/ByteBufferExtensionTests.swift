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

final class ByteBufferExtensionTests: XCTestCase {

    func testSkipRawBytesChunkedInformsAboutMissingDataIfNeeded() {
        // empty buffer needs more bytes
        var buffer = ByteBuffer()
        XCTAssertFalse(buffer.skipRawBytesChunked())
        // buffer contains less bytes then specified by length
        buffer = ByteBuffer(bytes: [5, 0, 0])
        XCTAssertFalse(buffer.skipRawBytesChunked())

        // expected
        buffer = ByteBuffer(bytes: [3, 0, 0, 0])
        XCTAssertTrue(buffer.skipRawBytesChunked())

        // long length without any data
        buffer = ByteBuffer(integer: Constants.TNS_LONG_LENGTH_INDICATOR)
        XCTAssertFalse(buffer.skipRawBytesChunked())
        // long length without enough data after length
        buffer = ByteBuffer(integer: Constants.TNS_LONG_LENGTH_INDICATOR)
        buffer.writeUB4(300)
        buffer.writeRepeatingByte(0, count: 260)
        XCTAssertFalse(buffer.skipRawBytesChunked())
        // long length without enough bytes for full second length
        buffer = ByteBuffer(integer: Constants.TNS_LONG_LENGTH_INDICATOR)
        buffer.writeUB4(300)
        buffer.writeRepeatingByte(0, count: 300)
        buffer.writeInteger(UInt8(1))
        XCTAssertFalse(buffer.skipRawBytesChunked())
        // long length without enough data after second length
        buffer = ByteBuffer(integer: Constants.TNS_LONG_LENGTH_INDICATOR)
        buffer.writeUB4(300)
        buffer.writeRepeatingByte(0, count: 300)
        buffer.writeUB4(2)
        XCTAssertFalse(buffer.skipRawBytesChunked())

        // expected
        buffer = ByteBuffer(integer: Constants.TNS_LONG_LENGTH_INDICATOR)
        buffer.writeUB4(300)
        buffer.writeRepeatingByte(0, count: 300)
        buffer.writeUB4(0)
        XCTAssertTrue(buffer.skipRawBytesChunked())
    }

}
