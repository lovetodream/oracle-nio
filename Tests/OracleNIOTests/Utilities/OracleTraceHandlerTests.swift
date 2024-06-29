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

import Logging
import NIOConcurrencyHelpers
import NIOCore
import NIOEmbedded
import XCTest

@testable import OracleNIO

final class OracleTraceHandlerTests: XCTestCase {
    func testTracer() async throws {
        let lines: NIOLockedValueBox<[String]> = .init([])
        let logger = Logger(label: "Tracer") { _ in
            Handler(lines: lines)
        }
        let handler = OracleTraceHandler(connectionID: 1, logger: logger, shouldLog: true)
        let channel = await NIOAsyncTestingChannel(handler: handler)
        try await channel.connect(to: .makeAddressResolvingHost("127.0.0.1", port: 1521))
        let buffer = ByteBuffer(bytes: [
            0x0, 0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7,
            0x8, 0x9, 0xa, 0xb, 0xc, 0xd, 0xe, 0xf,
            UInt8(ascii: "a"),
        ])
        try await channel.writeInbound(buffer)
        do {
            let lines = lines.withLockedValue { $0 }
            XCTAssertEqual(lines.count, 1)
            XCTAssertEqual(
                lines.first,
                """
                Receiving packet [op 1] on socket 1
                0000 : 00 01 02 03 04 05 06 07 |........|
                0008 : 08 09 0A 0B 0C 0D 0E 0F |........|
                0016 : 61                      |a       |

                """)
        }
        try await channel.writeOutbound(buffer)
        do {
            let lines = lines.withLockedValue { $0 }
            XCTAssertEqual(lines.count, 2)
            XCTAssertEqual(
                lines.last,
                """
                Sending packet [op 2] on socket 1
                0000 : 00 01 02 03 04 05 06 07 |........|
                0008 : 08 09 0A 0B 0C 0D 0E 0F |........|
                0016 : 61                      |a       |

                """)
        }
    }

    final class Handler: LogHandler {
        var metadata: Logger.Metadata = [:]
        var logLevel: Logger.Level = .trace

        let lines: NIOLockedValueBox<[String]>

        init(lines: NIOLockedValueBox<[String]>) {
            self.lines = lines
        }

        subscript(metadataKey key: String) -> Logger.Metadata.Value? {
            get {
                metadata[key]
            }
            set(newValue) {
                metadata[key] = newValue
            }
        }

        func log(
            level: Logger.Level,
            message: Logger.Message,
            metadata: Logger.Metadata?,
            source: String,
            file: String,
            function: String,
            line: UInt
        ) {
            lines.withLockedValue {
                $0.append(message.description)
            }
        }
    }
}
