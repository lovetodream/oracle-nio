//===----------------------------------------------------------------------===//
//
// This source file is part of the OracleNIO open source project
//
// Copyright (c) 2024 Timo Zacherl and the OracleNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
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

// snippet.connect
let connection = try await OracleConnection.connect(configuration: configuration, id: 1)
// snippet.end

// snippet.use
try await connection.execute("SELECT 'Hello, World!' FROM dual")
// snippet.end

// snippet.close
try await connection.close()
// snippet.end
