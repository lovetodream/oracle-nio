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
import XCTest

@testable import OracleNIO

final class OracleConnectionTests: XCTestCase {

    func testWeDoNotCrashOnUnexpectedChannelEvents() async throws {
        let (_, channel) = try await self.makeTestConnectionWithAsyncTestingChannel()

        enum MyEvent {
            case pleaseDoNotCrash
        }
        channel.pipeline.fireUserInboundEventTriggered(MyEvent.pleaseDoNotCrash)
    }

    func testConnectionOnClosedChannelFails() async throws {
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
        XCTAssertEqual(
            thrown, OracleSQLError.connectionError(underlying: ChannelError.alreadyClosed))
    }

    func testConfigurationChangesAreReflected() {
        var configuration = OracleConnection.Configuration(
            host: "localhost",
            port: 1521,
            service: .serviceName("oracle"),
            username: "username",
            password: "password"
        )
        XCTAssertEqual(configuration.host, "localhost")
        XCTAssertEqual(configuration.port, 1521)
        XCTAssertEqual(
            configuration.endpointInfo,
            .connectTCP(host: "localhost", port: 1521)
        )
        configuration.host = "127.0.0.1"
        configuration.port = 1522
        XCTAssertEqual(configuration.host, "127.0.0.1")
        XCTAssertEqual(configuration.port, 1522)
        XCTAssertEqual(
            configuration.endpointInfo,
            .connectTCP(host: "127.0.0.1", port: 1522)
        )

        do {  // established channel host and port are not mutable
            let channel = NIOAsyncTestingChannel()
            var configuration = OracleConnection.Configuration(
                establishedChannel: channel,
                service: .serviceName("oracle"),
                username: "username",
                password: "password"
            )
            XCTAssertEqual(configuration.host, "")
            XCTAssertEqual(configuration.port, 1521)
            XCTAssertEqual(configuration.endpointInfo, .configureChannel(channel))
            configuration.host = "127.0.0.1"
            configuration.port = 1522
            XCTAssertEqual(configuration.host, "")
            XCTAssertEqual(configuration.port, 1521)
            XCTAssertEqual(configuration.endpointInfo, .configureChannel(channel))
        }
    }


    // MARK: Utility

    typealias C = OracleBackendMessageDecoder.Container
    func makeTestConnectionWithAsyncTestingChannel() async throws -> (
        OracleConnection, NIOAsyncTestingChannel
    ) {
        let eventLoop = NIOAsyncTestingEventLoop()
        let protocolVersion =
            OracleBackendMessageEncoder
            .ProtocolVersion(Int(Constants.TNS_VERSION_MINIMUM))
        let channel = await NIOAsyncTestingChannel(
            handlers: [
                ReverseByteToMessageHandler(OracleFrontendMessageDecoder()),
                ReverseMessageToByteHandler(
                    OracleBackendMessageEncoder(protocolVersion: protocolVersion)),
            ],
            loop: eventLoop
        )
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
        XCTAssertEqual(connect, .connect)
        try await channel.writeInbound(
            C(messages: [
                OracleBackendMessage.accept(.init(newCapabilities: .desired()))
            ]))
        protocolVersion.value = Int(Constants.TNS_VERSION_DESIRED)

        let fastAuth = try await channel.waitForOutboundWrite(as: OracleFrontendMessage.self)
        XCTAssertEqual(fastAuth, .fastAuth)
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
        XCTAssertEqual(authPhase2, .authPhaseTwo)
        try await channel.writeInbound(
            C(messages: [
                .parameter([
                    "AUTH_VERSION_NO": .init(value: "386138501", flags: 0),
                    "AUTH_SESSION_ID": .init(value: "52", flags: 0),
                    "AUTH_SERIAL_NUM": .init(value: "11865", flags: 0),
                ])
            ]))

        let connection = try await connectionPromise
        XCTAssertEqual("\(connection.serverVersion)", "23.4.0.24.5")

        self.addTeardownBlock {
            async let closePromise: Void = connection.close()
            let logoff = try await channel.waitForOutboundWrite(as: OracleFrontendMessage.self)
            XCTAssertEqual(logoff, .logoff)
            try await channel.writeInbound(
                C(messages: [
                    .status(.init(callStatus: 0, endToEndSequenceNumber: 0))
                ]))
            let close = try await channel.waitForOutboundWrite(as: OracleFrontendMessage.self)
            XCTAssertEqual(close, .close)
            try await closePromise
        }

        return (connection, channel)
    }
}

extension Capabilities {
    static func desired() -> Capabilities {
        var caps = Capabilities()
        caps.protocolVersion = Constants.TNS_VERSION_DESIRED
        caps.supportsFastAuth = true
        return caps
    }
}

#if compiler(>=6.0)
    extension OracleConnection.Configuration.EndpointInfo: @retroactive Equatable {}
#else
    extension OracleConnection.Configuration.EndpointInfo: Equatable {}
#endif
extension OracleConnection.Configuration.EndpointInfo {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.configureChannel(let lhs), .configureChannel(let rhs)):
            return lhs === rhs
        case (.connectTCP(let lhsHost, let lhsPort), .connectTCP(let rhsHost, let rhsPort)):
            return lhsHost == rhsHost && lhsPort == rhsPort
        default:
            return false
        }
    }

}
