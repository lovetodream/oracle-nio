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

import OracleNIO

// snippet.configuration
let configuration = OracleConnection.Configuration(
    host: "localhost",
    service: .serviceName("my_service_name"),
    username: "my_username",
    password: "my_password"
)
// snippet.end

// snippet.makeClient
let client = OracleClient(configuration: configuration)
// snippet.end

// snippet.run
await withTaskGroup(of: Void.self) { taskGroup in
    taskGroup.addTask {
        await client.run()  // !important
    }

    // You can use the client while the `client.run()` method is not cancelled.

    // To shutdown the client, cancel its run method, by cancelling the taskGroup.
    taskGroup.cancelAll()
}
// snippet.end
