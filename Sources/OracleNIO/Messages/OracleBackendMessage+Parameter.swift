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

import class Foundation.NSDictionary

extension OracleBackendMessage {
    struct Parameter: PayloadDecodable, ExpressibleByDictionaryLiteral, Hashable {

        typealias Key = String
        struct Value: Hashable {
            let value: String
            let flags: UInt32?
        }


        var elements: [Key: Value]

        internal init(_ elements: [Key: Value]) {
            self.elements = elements
        }

        internal init(
            dictionaryLiteral elements:
                (Key, Value)...
        ) {
            self.elements = .init(uniqueKeysWithValues: elements)
        }

        subscript(key: Key) -> Value? {
            get { return elements[key] }
        }

        static func decode(
            from buffer: inout ByteBuffer,
            context: OracleBackendMessageDecoder.Context
        ) throws -> OracleBackendMessage.Parameter {
            let numberOfParameters = buffer.readUB2() ?? 0
            var elements = [Key: Value]()
            for _ in 0..<numberOfParameters {
                buffer.skipUB4()
                let key = try buffer.readString()
                let length = buffer.readUB4() ?? 0
                let value =
                    if length > 0 { try buffer.readString() } else { "" }
                let flags = buffer.readUB4()
                elements[key] = .init(value: value, flags: flags)
            }
            return .init(elements)
        }
    }

    struct QueryParameter: PayloadDecodable, Hashable {
        var schema: String?
        var edition: String?
        var rowCounts: [UInt64]?

        static func decode(
            from buffer: inout ByteBuffer,
            context: OracleBackendMessageDecoder.Context
        ) throws -> OracleBackendMessage.QueryParameter {
            let parametersCount = buffer.readUB2() ?? 0  // al8o4l (ignored)
            for _ in 0..<parametersCount {
                buffer.skipUB4()
            }
            if let bytesCount = buffer.readUB2()  // al8txl (ignored)
                .flatMap(Int.init), bytesCount > 0
            {
                buffer.moveReaderIndex(forwardBy: bytesCount)
            }
            let pairsCount = buffer.readUB2() ?? 0  // number of key/value pairs
            var schema: String? = nil
            var edition: String? = nil
            var rowCounts: [UInt64]? = nil
            for _ in 0..<pairsCount {
                var keyValue: ByteBuffer? = nil
                if let bytesCount = buffer.readUB2(), bytesCount > 0 {  // key
                    keyValue =
                        try buffer.throwingReadOracleSpecificLengthPrefixedSlice()
                }
                if let bytesCount = buffer.readUB2(), bytesCount > 0 {  // value
                    buffer.skipRawBytesChunked()
                }
                let keywordNumber = buffer.readUB2() ?? 0  // keyword number
                if keywordNumber == Constants.TNS_KEYWORD_NUM_CURRENT_SCHEMA,
                    let keyValue
                {
                    schema = keyValue.getString(
                        at: 0, length: keyValue.readableBytes
                    )
                } else if keywordNumber == Constants.TNS_KEYWORD_NUM_EDITION,
                    let keyValue
                {
                    edition = keyValue.getString(
                        at: 0, length: keyValue.readableBytes
                    )
                }
            }
            if let bytesCount = buffer.readUB2().flatMap(Int.init),
                bytesCount > 0
            {
                buffer.moveReaderIndex(forwardBy: bytesCount)
            }
            if context.statementOptions!.arrayDMLRowCounts == true {
                let numberOfRows = buffer.readUB4() ?? 0
                rowCounts = []
                for _ in 0..<numberOfRows {
                    let rowCount = buffer.readUB8() ?? 0
                    rowCounts?.append(rowCount)
                }
            }
            return .init(schema: schema, edition: edition, rowCounts: rowCounts)
        }
    }

    struct LOBParameter: PayloadDecodable, Hashable {
        let amount: Int64?
        let boolFlag: Bool?

        static func decode(
            from buffer: inout ByteBuffer,
            context: OracleBackendMessageDecoder.Context
        ) throws -> OracleBackendMessage.LOBParameter {
            if let sourceLOB = context.lobContext?.sourceLOB {
                try sourceLOB.locator.withLockedValue {
                    guard let newLocator = buffer.readBytes(length: $0.count) else {
                        throw MissingDataDecodingError.Trigger()
                    }
                    $0 = newLocator
                }
            }
            if let destinationLOB = context.lobContext?.destinationLOB {
                try destinationLOB.locator.withLockedValue {
                    guard let newLocator = buffer.readBytes(length: $0.count) else {
                        throw MissingDataDecodingError.Trigger()
                    }
                    $0 = newLocator
                }
            }
            let amount: Int64?
            if context.lobContext?.operation == .createTemp {
                buffer.skipUB2()  // skip character set
                // skip trailing flags, amount
                buffer.moveReaderIndex(forwardBy: 3)
                amount = nil
            } else if context.lobContext?.sendAmount == true {
                amount = try buffer.throwingReadSB8()
            } else {
                amount = nil
            }
            let boolFlag: Bool?
            if context.lobContext?.operation == .isOpen {
                // flag
                boolFlag = try buffer.throwingReadInteger(as: UInt8.self) > 0
            } else {
                boolFlag = nil
            }
            context.lobContext = nil
            return .init(amount: amount, boolFlag: boolFlag)
        }
    }
}
