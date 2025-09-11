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
import NIOEmbedded
import Testing

@testable import OracleNIO

private typealias RowData = OracleBackendMessage.RowData

@Suite(.timeLimit(.minutes(5))) struct RowDataTests {

    @Test func processVectorColumnDataRequestsMissingData() {
        let type = OracleDataType.vector

        var buffer = ByteBuffer(bytes: [
            1, 1,  // length
            0,  // size
            0,  // chunk size
            1,  // value (partial)
        ])
        #expect(
            throws: MissingDataDecodingError.Trigger(),
            performing: {
                try RowData.decode(from: &buffer, context: .init(columns: type))
            })

        buffer = ByteBuffer(bytes: [
            1, 1,  // length
            0,  // size
            0,  // chunk size
            1, 1,  // value
            1,  // locator (partial)
        ])
        #expect(
            throws: MissingDataDecodingError.Trigger(),
            performing: {
                try RowData.decode(from: &buffer, context: .init(columns: type))
            })
    }

    @Test func processObjectColumnDataRequestsMissingData() throws {
        let type = OracleDataType.object

        var buffer = ByteBuffer(bytes: [1, 1])  // type oid
        #expect(
            throws: MissingDataDecodingError.Trigger(),
            performing: {
                try RowData.decode(from: &buffer, context: .init(columns: type))
            })

        buffer = ByteBuffer(bytes: [
            1, 1, 0,  // type oid
            1, 1,  // oid
        ])
        #expect(
            throws: MissingDataDecodingError.Trigger(),
            performing: {
                try RowData.decode(from: &buffer, context: .init(columns: type))
            })

        buffer = ByteBuffer(bytes: [
            1, 1, 0,  // type oid
            1, 1, 0,  // oid
            1, 1,  // snapshot
        ])
        #expect(
            throws: MissingDataDecodingError.Trigger(),
            performing: {
                try RowData.decode(from: &buffer, context: .init(columns: type))
            })

        buffer = ByteBuffer(bytes: [
            1, 1, 0,  // type oid
            1, 1, 0,  // oid
            1, 1, 0,  // snapshot
            0,  // version
            0,  // data length
            0,  // flags
        ])
        #expect(
            throws: Never.self,
            performing: {
                try RowData.decode(from: &buffer, context: .init(columns: type))
            })
    }

    @Test func processLOBColumnDataRequestsMissingData() throws {
        let type = OracleDataType.blob

        var buffer = ByteBuffer(bytes: [
            1, 1,  // length
            1, 1,  // size
            1, 1,  // chunk size
            2, 0,  // locator (partial)
        ])
        #expect(
            throws: MissingDataDecodingError.Trigger(),
            performing: {
                try RowData.decode(from: &buffer, context: .init(columns: type))
            })

        buffer = ByteBuffer(bytes: [
            1, 1,  // length
            1, 1,  // size
            1, 1,  // chunk size
            1, 0,  // locator
        ])
        #expect(
            throws: Never.self,
            performing: {
                try RowData.decode(from: &buffer, context: .init(columns: type))
            })

        buffer = ByteBuffer(bytes: [0])
        #expect(
            throws: Never.self,
            performing: {
                try RowData.decode(from: &buffer, context: .init(columns: type))
            })
    }

    @Test func processBufferSizeZero() throws {
        var buffer = ByteBuffer()
        let context = OracleBackendMessageDecoder.Context(capabilities: .init())
        context.statementContext = .init(statement: "")
        context.describeInfo = .init(columns: [
            .init(
                name: "",
                dataType: .varchar,
                dataTypeSize: 0,
                precision: 0,
                scale: 0,
                bufferSize: 0,
                nullsAllowed: true,
                typeScheme: nil,
                typeName: nil,
                domainSchema: nil,
                domainName: nil,
                annotations: [:],
                vectorDimensions: nil,
                vectorFormat: nil
            )
        ])
        let result = try RowData.decode(from: &buffer, context: context)
        #expect(result == .init(columns: [.data(ByteBuffer(bytes: [0]))]))
    }

    @Test func emptyRowID() throws {
        var buffer = ByteBuffer(bytes: [0])
        let context = OracleBackendMessageDecoder.Context(columns: .rowID)
        let result = try RowData.decode(from: &buffer, context: context)
        #expect(result == .init(columns: [.data(ByteBuffer(bytes: [0]))]))
    }

    @Test func emptyBufferZeroActualBytes() throws {
        var buffer = ByteBuffer(bytes: [0, 1, 255])
        let context = OracleBackendMessageDecoder.Context(capabilities: .init())
        let promise = EmbeddedEventLoop().makePromise(of: OracleRowStream.self)
        promise.fail(StatementContext.TestComplete())
        var statement: OracleStatement = ""
        statement.binds.append(.init(dataType: .boolean), bindName: "1")
        context.statementContext = .init(statement: statement)
        let result = try RowData.decode(from: &buffer, context: context)
        #expect(result == .init(columns: [.data(ByteBuffer(bytes: [0]))]))
    }
}
