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

final class AuthenticationPhaseTwoMessageTests: XCTestCase {
    let testPrivateKey = """
        -----BEGIN RSA PRIVATE KEY-----
        MIICWgIBAAKBgGhXeKN8/4vESCXIgvZV+61Pp8sCWlnBGuOSgQ0wAHzvz9VVm8fs
        2k69hhzpYWsbmlpEUTNZaSsdxIVqKuo0dLrA/cK4CRJI4t35PmIlaEF852nk+5nL
        azYmurtyl1LwMTJ9toC9d1TpM5+Fl/aXQ8SP2Kycaw/9P9HNSQPSxqsrAgMBAAEC
        gYAE1dDcWqWI946UWadf/PoNvPw8lx5SvHUfiKF8V/Yd1AsgirgOWrZ/IZ8+Zb5C
        9WOAvVu58nHCMr3xpMraUZX7JmFXRjRZ/uRjxlbj4zwEZkTqfNdOOzHb5XSgQBWe
        +w+MWEOUP647SmCGMvwjzVZIYNwBz9RXx8M+Odp/ti7/sQJBAKecghe+0jHDyDxT
        K2wkxvZ6tdDIr/MGxo4uT/bXbxpBVhmyx2TIDBrISjxjTOyOTi8nglkHrBA7zjSX
        JIkeGgMCQQCfXZKZEoPtHFTP/1dAJDyLijoKxoFyjtP2k4Z7VsUt+rNbAGSxkvbS
        T/kxvlUUfYPv3+Q6m9DTDR5kywdFC/W5AkB8FxsZiWUFAvXT859KSVAkW2UQVgQt
        4O5PhWoeThErVwPvsrR8oL6VdYPAgaQJ3rFzp8SRNWTl/+ECfoPGIEsRAkBVNDMv
        0f1k5TPXLP6aFYWlWVbk8fK9q+1ZtNA+20p65cHE0rYDVr7N/OIPnWJhnSXQNxUP
        3MTOQgJRA1e0q8tJAkAUYktgG/+Zu0OKmRLRKQEe0XZ69lN7+rtUWfm9O4pCc+CD
        kbg+3wsQXo3qc85xJMKZabpbW4Gj5p6qqpm2wd2e
        -----END RSA PRIVATE KEY-----
        """

    func testEncodeWithTokenAndPrivateKeyDoesNotFailWithValidKey() throws {
        let context = AuthContext(
            method: .init(token: .tokenAndPrivateKey(token: "my_token", key: testPrivateKey)),
            service: .serviceName("test"),
            terminalName: "terminal",
            programName: "program",
            machineName: "machine",
            pid: 1,
            processUsername: "user",
            mode: .sysDBA,
            description: .init(
                connectionID: "1",
                addressLists: [],
                service: .serviceName("test"),
                sslServerDnMatch: false,
                purity: .new
            )
        )
        var encoder = OracleFrontendMessageEncoder(buffer: .init(), capabilities: .init())
        try encoder.authenticationPhaseTwo(authContext: context, parameters: .init([:]))
    }
}
