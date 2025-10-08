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
import NIOCore
import NIOEmbedded
import Testing

@testable import OracleNIO

@Suite(.timeLimit(.minutes(5))) struct OracleConnectionTests {

    @Test func weDoNotCrashOnUnexpectedChannelEvents() async throws {
        try await self.useTestConnectionWithAsyncTestingChannel { _, channel in
            enum MyEvent {
                case pleaseDoNotCrash
            }
            channel.pipeline.fireUserInboundEventTriggered(MyEvent.pleaseDoNotCrash)
        }
    }

    @Test func connectionOnClosedChannelFails() async throws {
        let eventLoop = NIOAsyncTestingEventLoop()
        let channel = NIOAsyncTestingChannel(loop: eventLoop)
        try await channel.connect(to: .makeAddressResolvingHost("localhost", port: 1521))
        try await channel.close()

        let configuration = OracleConnection.Configuration(
            establishedChannel: channel,
            service: .serviceName("oracle"),
            username: "username",
            password: "password"
        )

        var thrown: OracleSQLError?
        do {
            _ = try await OracleConnection.connect(
                on: eventLoop,
                configuration: configuration,
                id: 1,
                logger: Logger(label: "OracleConnectionTests")
            )
        } catch let error as OracleSQLError {
            thrown = error
        }
        #expect(thrown == OracleSQLError.connectionError(underlying: ChannelError.alreadyClosed))
    }

    @Test func configurationChangesAreReflected() {
        var configuration = OracleConnection.Configuration(
            host: "localhost",
            port: 1521,
            service: .serviceName("oracle"),
            username: "username",
            password: "password"
        )
        #expect(configuration.host == "localhost")
        #expect(configuration.port == 1521)
        #expect(configuration.endpointInfo == .connectTCP(host: "localhost", port: 1521))
        configuration.host = "127.0.0.1"
        configuration.port = 1522
        #expect(configuration.host == "127.0.0.1")
        #expect(configuration.port == 1522)
        #expect(configuration.endpointInfo == .connectTCP(host: "127.0.0.1", port: 1522))

        do {  // established channel host and port are not mutable
            let channel = NIOAsyncTestingChannel()
            var configuration = OracleConnection.Configuration(
                establishedChannel: channel,
                service: .serviceName("oracle"),
                username: "username",
                password: "password"
            )
            #expect(configuration.host == "")
            #expect(configuration.port == 1521)
            #expect(configuration.endpointInfo == .configureChannel(channel))
            configuration.host = "127.0.0.1"
            configuration.port = 1522
            #expect(configuration.host == "")
            #expect(configuration.port == 1521)
            #expect(configuration.endpointInfo == .configureChannel(channel))
        }
    }

    @Test func oobCheckWorks() async throws {
        func runTest(supportsOOB: Bool) async throws {
            let eventLoop = NIOAsyncTestingEventLoop()
            let protocolVersion =
                OracleBackendMessageEncoder
                .ProtocolVersion(Int(Constants.TNS_VERSION_MINIMUM))
            let channel = try await NIOAsyncTestingChannel(loop: eventLoop) { channel in
                try channel.pipeline.syncOperations.addHandler(
                    ReverseByteToMessageHandler(OracleFrontendMessageDecoder()))
                try channel.pipeline.syncOperations.addHandler(
                    ReverseMessageToByteHandler(OracleBackendMessageEncoder(protocolVersion: protocolVersion))
                )
            }
            try await channel.connect(to: .makeAddressResolvingHost("localhost", port: 1521))

            let configuration = OracleConnection.Configuration(
                establishedChannel: channel,
                service: .serviceName("oracle"),
                username: "username",
                password: "password"
            )

            async let connectionPromise = OracleConnection.connect(
                on: eventLoop,
                configuration: configuration,
                id: 1,
                logger: Logger(label: "OracleConnectionTests")
            )

            let connect = try await channel.waitForOutboundWrite(as: OracleFrontendMessage.self)
            #expect(connect == .connect)
            try await channel.writeInbound(
                C(messages: [
                    OracleBackendMessage.accept(.init(newCapabilities: .desired(supportsOOB: true)))
                ]))
            protocolVersion.value.withLockedValue({ $0 = Int(Constants.TNS_VERSION_DESIRED) })

            let oob = try await channel.waitForOutboundWrite(as: OracleFrontendMessage.self)
            #expect(oob == .oob)
            let marker = try await channel.waitForOutboundWrite(as: OracleFrontendMessage.self)
            #expect(marker == .marker)
            if supportsOOB {
                try await channel.writeInbound(C(messages: [.marker]))
            } else {
                try await channel.writeInbound(C(messages: [.resetOOB]))
            }

            let fastAuth = try await channel.waitForOutboundWrite(as: OracleFrontendMessage.self)
            #expect(fastAuth == .fastAuth)
            try await channel.writeInbound(
                C(messages: [
                    .parameter([
                        "AUTH_PBKDF2_CSK_SALT": .init(
                            value: "CA4861BD9A1BF3CC8DA26D236F7534E3", flags: 0),
                        "AUTH_SESSKEY": .init(
                            value: "9F9176A81D9B16F47685024821D6D80064C51B80CD70596C273A99C528599B8E",
                            flags: 0),
                        "AUTH_VFR_DATA": .init(
                            value: "48EE55C6694386C5D6DCCC51343193E0",
                            flags: Constants.TNS_VERIFIER_TYPE_12C),
                        "AUTH_PBKDF2_VGEN_COUNT": .init(value: "4096", flags: 0),
                        "AUTH_PBKDF2_SDER_COUNT": .init(value: "3", flags: 0),
                        "AUTH_GLOBALLY_UNIQUE_DBID\0": .init(
                            value: "5D7C6DF1436ADB3A97ED9E44F4C830F7", flags: 0),
                    ])
                ]))
            let authPhase2 = try await channel.waitForOutboundWrite(as: OracleFrontendMessage.self)
            #expect(authPhase2 == .authPhaseTwo)

            // bypass security check
            try await channel.pipeline.handler(type: OracleChannelHandler.self).map { $0.setComboKey(nil) }.get()

            try await channel.writeInbound(
                C(messages: [
                    .parameter([
                        "AUTH_VERSION_NO": .init(value: "386138501", flags: 0),
                        "AUTH_SESSION_ID": .init(value: "52", flags: 0),
                        "AUTH_SERIAL_NUM": .init(value: "11865", flags: 0),
                    ])
                ]))

            let connection = try await connectionPromise
            #expect("\(connection.serverVersion)" == "23.4.0.24.5")

            async let closePromise: Void = connection.close()
            let logoff = try await channel.waitForOutboundWrite(as: OracleFrontendMessage.self)
            #expect(logoff == .logoff)
            try await channel.writeInbound(
                C(messages: [
                    .status(.init(callStatus: 0, endToEndSequenceNumber: 0))
                ]))
            let close = try await channel.waitForOutboundWrite(as: OracleFrontendMessage.self)
            #expect(close == .close)
            try await closePromise
        }
        try await runTest(supportsOOB: true)
        try await runTest(supportsOOB: false)
    }


    // MARK: Utility

    typealias C = OracleBackendMessageDecoder.Container
    func useTestConnectionWithAsyncTestingChannel(
        _ work: @escaping (OracleConnection, NIOAsyncTestingChannel) async throws -> Void
    ) async throws {
        let eventLoop = NIOAsyncTestingEventLoop()
        let protocolVersion =
            OracleBackendMessageEncoder
            .ProtocolVersion(Int(Constants.TNS_VERSION_MINIMUM))
        let channel = try await NIOAsyncTestingChannel(loop: eventLoop) { channel in
            try channel.pipeline.syncOperations.addHandler(
                ReverseByteToMessageHandler(OracleFrontendMessageDecoder()))
            try channel.pipeline.syncOperations.addHandler(
                ReverseMessageToByteHandler(OracleBackendMessageEncoder(protocolVersion: protocolVersion))
            )
        }
        try await channel.connect(to: .makeAddressResolvingHost("localhost", port: 1521))

        let configuration = OracleConnection.Configuration(
            establishedChannel: channel,
            service: .serviceName("oracle"),
            username: "username",
            password: "password"
        )

        async let connectionPromise = OracleConnection.connect(
            on: eventLoop,
            configuration: configuration,
            id: 1,
            logger: Logger(label: "OracleConnectionTests")
        )

        let connect = try await channel.waitForOutboundWrite(as: OracleFrontendMessage.self)
        #expect(connect == .connect)
        try await channel.writeInbound(
            C(messages: [
                OracleBackendMessage.accept(.init(newCapabilities: .desired()))
            ]))
        protocolVersion.value.withLockedValue({ $0 = Int(Constants.TNS_VERSION_DESIRED) })

        let fastAuth = try await channel.waitForOutboundWrite(as: OracleFrontendMessage.self)
        #expect(fastAuth == .fastAuth)
        try await channel.writeInbound(
            C(messages: [
                .parameter([
                    "AUTH_PBKDF2_CSK_SALT": .init(
                        value: "D390EB852C15E0BB6D09B35634196549", flags: 0),
                    "AUTH_SESSKEY": .init(
                        value: "E25A7AE255A27542B254C2566696E7902F8C06DCB46CB30F1EA9D859F56B5C94",
                        flags: 0),
                    "AUTH_VFR_DATA": .init(
                        value: "CA52D77E4C359A2A5701E4DADB594963",
                        flags: Constants.TNS_VERIFIER_TYPE_12C),
                    "AUTH_PBKDF2_VGEN_COUNT": .init(value: "4096", flags: 0),
                    "AUTH_PBKDF2_SDER_COUNT": .init(value: "3", flags: 0),
                    "AUTH_GLOBALLY_UNIQUE_DBID\0": .init(
                        value: "EB3F4E21E6E94E317CBA938EE89045DF", flags: 0),
                ])
            ]))
        let authPhase2 = try await channel.waitForOutboundWrite(as: OracleFrontendMessage.self)
        #expect(authPhase2 == .authPhaseTwo)

        // bypass security check
        try await channel.pipeline.handler(type: OracleChannelHandler.self).map { $0.setComboKey(nil) }.get()

        try await channel.writeInbound(
            C(messages: [
                .parameter([
                    "AUTH_SC_REAL_DBUNIQUE_NAME": .init(value: "FREE", flags: 0),
                    "AUTH_LAST_LOGIN": .init(value: "787D0A0809112C000000000000", flags: 0),
                    "AUTH_DB_MOUNT_ID\0": .init(value: "1485978099", flags: 0),
                    "AUTH_SC_DB_DOMAIN": .init(value: "", flags: 0),
                    "AUTH_SC_SERVICE_NAME": .init(value: "freepdb1", flags: 0),
                    "AUTH_SC_INSTANCE_ID": .init(value: "1", flags: 0),
                    "AUTH_FAILOVER_ID": .init(value: "1", flags: 0),
                    "AUTH_INSTANCENAME": .init(value: "FREE", flags: 0),
                    "AUTH_NLS_LXCTERRITORY\0": .init(value: "AMERICA", flags: 0),
                    "AUTH_INSTANCE_NO": .init(value: "1", flags: 0),
                    "AUTH_NLS_LXCISOCURR\0": .init(value: "AMERICA", flags: 0),
                    "AUTH_NLS_LXCNUMERICS\0": .init(value: ".,", flags: 0),
                    "AUTH_NLS_LXCSORT\0": .init(value: "BINARY", flags: 0),
                    "AUTH_NLS_LXCCALENDAR\0": .init(value: "GREGORIAN", flags: 0),
                    "AUTH_DBNAME": .init(value: "FREEPDB1", flags: 0),
                    "AUTH_CAPABILITY_TABLE": .init(value: "", flags: 0),
                    "AUTH_NLS_LXCSTMPFM\0": .init(value: "DD-MON-RR HH.MI.SSXFF AM", flags: 0),
                    "AUTH_NLS_LXLENSEMANTICS\0": .init(value: "BYTE", flags: 0),
                    "AUTH_NLS_LXCCURRENCY\0": .init(value: "$", flags: 0),
                    "AUTH_USER_ID": .init(value: "135", flags: 0),
                    "AUTH_DB_ID\0": .init(value: "3633909673", flags: 0),
                    "AUTH_NLS_LXCDATEFM\0": .init(value: "DD-MON-RR", flags: 0),
                    "AUTH_NLS_LXCTIMEFM\0": .init(value: "HH.MI.SSXFF AM", flags: 0),
                    "AUTH_NLS_LXCOMP\0": .init(value: "BINARY", flags: 0),
                    "AUTH_SC_INSTANCE_START_TIME": .init(value: "2025-10-07 13:40:02.000000000 +02:00", flags: 0),
                    "AUTH_SVR_RESPONSE": .init(
                        value:
                            "C4E603425BC20DCA9E57FC105C3987CB224C390A0D8654D1CBBE10BA24B4D0F024E15A59728E5200106DF0F8A4F827F7",
                        flags: 0),
                    "AUTH_MAX_OPEN_CURSORS": .init(value: "300", flags: 0),
                    "AUTH_SERIAL_NUM": .init(value: "26498", flags: 0),
                    "AUTH_SC_SERVER_HOST": .init(value: "6a9ed88d2d29", flags: 0),
                    "AUTH_PDB_UID\0": .init(value: "3633909673", flags: 0),
                    "AUTH_NLS_LXCDATELANG\0": .init(value: "AMERICAN", flags: 0),
                    "AUTH_MAX_IDEN_LENGTH": .init(value: "128", flags: 0),
                    "AUTH_SC_DBUNIQUE_NAME": .init(value: "FREE", flags: 0),
                    "AUTH_NLS_LXCTTZNFM\0": .init(value: "HH.MI.SSXFF AM TZR", flags: 0),
                    "AUTH_FLAGS": .init(value: "1", flags: 0),
                    "AUTH_XACTION_TRAITS": .init(value: "3", flags: 0),
                    "AUTH_SESSION_ID": .init(value: "99", flags: 0),
                    "AUTH_SERVER_TYPE": .init(value: "1", flags: 0),
                    "AUTH_NLS_LXCSTZNFM\0": .init(value: "DD-MON-RR HH.MI.SSXFF AM TZR", flags: 0),
                    "AUTH_NLS_LXLAN\0": .init(value: "AMERICAN", flags: 0),
                    "AUTH_VERSION_NO": .init(value: "386466199", flags: 0),
                    "AUTH_NLS_LXNCHARCONVEXCP\0": .init(value: "FALSE", flags: 0),
                    "AUTH_SC_INSTANCE_NAME": .init(value: "FREE", flags: 0),
                    "AUTH_VERSION_STRING": .init(value: "- Develop, Learn, and Run for Free", flags: 0),
                    "AUTH_NLS_LXCUNIONCUR\0": .init(value: "$", flags: 0),
                    "AUTH_SERVER_PID": .init(value: "2284", flags: 0),
                    "AUTH_VERSION_SQL": .init(value: "25", flags: 0),
                    "AUTH_VERSION_STATUS": .init(value: "0", flags: 0),
                ])
            ]))

        let connection = try await connectionPromise
        #expect("\(connection.serverVersion)" == "23.9.0.25.7")

        try await work(connection, channel)

        async let closePromise: Void = connection.close()
        let logoff = try await channel.waitForOutboundWrite(as: OracleFrontendMessage.self)
        #expect(logoff == .logoff)
        try await channel.writeInbound(
            C(messages: [
                .status(.init(callStatus: 0, endToEndSequenceNumber: 0))
            ]))
        let close = try await channel.waitForOutboundWrite(as: OracleFrontendMessage.self)
        #expect(close == .close)
        try await closePromise
    }
}
