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

import Foundation
import Logging
import NIOCore
import NIOSSL
import OracleNIO

extension OracleConnection {

    static func testConfig() throws -> OracleConnection.Configuration {

        var config = OracleConnection.Configuration(
            host: env("ORA_HOSTNAME") ?? "192.168.1.24",
            port: env("ORA_PORT").flatMap(Int.init) ?? 1521,
            service: .serviceName(env("ORA_SERVICE_NAME") ?? "XEPDB1"),
            username: env("ORA_USERNAME") ?? "my_user",
            password: env("ORA_PASSWORD") ?? "my_passwor"
        )

        if let wallet = env("ORA_TEST_WALLET")?.data(using: .utf8).flatMap(Array.init),
            let walletPassword = env("ORA_TEST_WALLET_PASSWORD")
        {
            let key = try NIOSSLPrivateKey(bytes: wallet, format: .pem) { completion in
                completion(walletPassword.utf8)
            }
            let certificate = try NIOSSLCertificate(bytes: wallet, format: .pem)

            var tls = TLSConfiguration.makeClientConfiguration()
            tls.privateKey = NIOSSLPrivateKeySource.privateKey(key)
            tls.certificateChain = [.certificate(certificate)]
            config.tls = try .require(.init(configuration: tls))
            config.retryCount = 20
            config.retryDelay = 3
        }

        return config
    }

    static func privilegedTestConfig() throws -> OracleConnection.Configuration {
        var config = try self.testConfig()
        config.authenticationMethod = {
            .init(
                username: "SYS",
                password: env("ORA_SYS_PASSWORD") ?? "my_very_secure_password")
        }
        config.mode = .sysDBA
        return config
    }

    static func test(
        on eventLoop: EventLoop = OracleConnection.defaultEventLoopGroup.any(),
        config: OracleConnection.Configuration? = nil,
        logLevel: Logger.Level = Logger.getLogLevel()
    ) async throws -> OracleConnection {
        var logger = Logger(label: "oracle.connection.test")
        logger.logLevel = logLevel

        return try await OracleConnection.connect(
            on: eventLoop,
            configuration: config ?? self.testConfig(),
            id: 0,
            logger: logger
        )
    }
}

extension Logger {
    static var oracleTest: Logger {
        var logger = Logger(label: "oracle.test")
        logger.logLevel = self.getLogLevel()
        return logger
    }

    static func getLogLevel() -> Logger.Level {
        let ghActionsDebug = env("ACTIONS_STEP_DEBUG")
        if ghActionsDebug == "true" || ghActionsDebug == "TRUE" {
            return .trace
        }

        return env("LOG_LEVEL").flatMap {
            Logger.Level(rawValue: $0)
        } ?? .debug
    }
}

func env(_ name: String) -> String? {
    getenv(name).flatMap { String(cString: $0) }
}
