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

extension OracleBackendMessage {
    struct RowData: PayloadDecodable, Sendable, Hashable {
        var columns: [ColumnStorage]

        enum ColumnStorage: Sendable, Hashable {
            case data(ByteBuffer)
            case duplicate(Int)
        }

        static func decode(
            from buffer: inout ByteBuffer,
            context: OracleBackendMessageDecoder.Context
        ) throws -> RowData {
            guard let statementContext = context.statementContext else {
                preconditionFailure(
                    "RowData cannot be received without having a \(String(reflecting: StatementContext.self))"
                )
            }

            let describeInfo =
                switch context.statementContext?.type {
                case .cursor(let cursor, _):
                    cursor.describeInfo
                default:
                    context.describeInfo
                }

            let columns: [ColumnStorage]
            if let describeInfo {
                columns = try self.processRowData(
                    from: &buffer,
                    describeInfo: describeInfo,
                    context: context
                )
            } else {
                columns = try self.processBindRow(
                    from: &buffer,
                    statementContext: statementContext,
                    capabilities: context.capabilities
                )
            }

            return .init(columns: columns)
        }

        private static func isDuplicateData(
            columnNumber: UInt32, bitVector: [UInt8]?
        ) -> Bool {
            guard let bitVector else { return false }
            let byteNumber = columnNumber / 8
            let bitNumber = columnNumber % 8
            return bitVector[Int(byteNumber)] & (1 << bitNumber) == 0
        }

        private static func processRowData(
            from buffer: inout ByteBuffer,
            describeInfo: DescribeInfo,
            context: OracleBackendMessageDecoder.Context
        ) throws -> [ColumnStorage] {
            var columns = [ColumnStorage]()
            columns.reserveCapacity(describeInfo.columns.count)
            for (index, column) in describeInfo.columns.enumerated() {
                if self.isDuplicateData(
                    columnNumber: UInt32(index),
                    bitVector: context.bitVector
                ) {
                    columns.append(.duplicate(index))
                } else {
                    let data = try self.processColumnData(
                        from: &buffer,
                        oracleType: column.dataType._oracleType,
                        csfrm: column.dataType.csfrm,
                        bufferSize: column.bufferSize,
                        capabilities: context.capabilities
                    )
                    columns.append(.data(data))
                }
            }

            // reset bit vector after usage
            context.bitVector = nil
            return columns
        }

        private static func processColumnData(
            from buffer: inout ByteBuffer,
            oracleType: _TNSDataType?,
            csfrm: UInt8,
            bufferSize: UInt32,
            capabilities: Capabilities
        ) throws -> ByteBuffer {
            var columnValue: ByteBuffer
            if bufferSize == 0 && ![.long, .longRAW, .uRowID].contains(oracleType) {
                columnValue = ByteBuffer(bytes: [0])  // NULL indicator
                return columnValue
            }

            if [.varchar, .char, .long].contains(oracleType) {
                if csfrm == Constants.TNS_CS_NCHAR {
                    try capabilities.checkNCharsetID()
                }
                // if we need capabilities during decoding in the future, we should
                // move this to decoding too
            }

            switch oracleType {
            case .varchar, .char, .long, .raw, .longRAW, .number, .date, .timestamp,
                .timestampLTZ, .timestampTZ, .binaryDouble, .binaryFloat,
                .binaryInteger, .boolean, .intervalDS:
                switch buffer.readOracleSlice() {
                case .some(let slice):
                    columnValue = slice
                case .none:
                    throw MissingDataDecodingError.Trigger()
                }
            case .rowID:
                // length is not the actual length of row ids
                let length = try buffer.throwingReadInteger(as: UInt8.self)
                if length == 0 || length == Constants.TNS_NULL_LENGTH_INDICATOR {
                    columnValue = ByteBuffer(bytes: [0])  // NULL indicator
                } else {
                    columnValue = ByteBuffer()
                    try columnValue.writeLengthPrefixed(as: UInt8.self) {
                        let start = buffer.readerIndex
                        _ = try RowID(from: &buffer, type: .rowID, context: .default)
                        let end = buffer.readerIndex
                        buffer.moveReaderIndex(to: start)
                        return $0.writeImmutableBuffer(buffer.readSlice(length: end - start)!)
                    }
                }
            case .cursor:
                buffer.moveReaderIndex(forwardBy: 1)  // length (fixed value)

                let readerIndex = buffer.readerIndex
                _ = try DescribeInfo._decode(
                    from: &buffer, context: .init(capabilities: capabilities)
                )
                buffer.skipUB2()  // cursor id
                let length = buffer.readerIndex - readerIndex
                buffer.moveReaderIndex(to: readerIndex)
                columnValue = ByteBuffer(integer: Constants.TNS_LONG_LENGTH_INDICATOR)
                try columnValue.writeLengthPrefixed(as: UInt32.self) { base in
                    let start = base.writerIndex
                    try capabilities.encode(into: &base)
                    base.writeImmutableBuffer(buffer.readSlice(length: length)!)
                    return base.writerIndex - start
                }
                columnValue.writeInteger(0, as: UInt32.self)  // chunk length of zero
            case .clob, .blob:

                // LOB has a UB4 length indicator instead of the usual UInt8
                let length = try buffer.throwingReadUB4()
                if length > 0 {
                    let size = try buffer.throwingReadUB8()
                    let chunkSize = try buffer.throwingReadUB4()
                    var locator: ByteBuffer
                    switch buffer.readOracleSlice() {
                    case .some(let slice):
                        locator = slice
                    case .none:
                        throw MissingDataDecodingError.Trigger()
                    }
                    columnValue = ByteBuffer()
                    try columnValue.writeLengthPrefixed(as: UInt8.self) {
                        $0.writeInteger(size) + $0.writeInteger(chunkSize)
                            + $0.writeBuffer(&locator)
                    }
                } else {
                    columnValue = .init(bytes: [0])  // empty buffer
                }
            case .json:
                // TODO: OSON
                // OSON has a UB4 length indicator instead of the usual UInt8
                fatalError("OSON is not yet implemented, will be added in the future")
            case .vector:
                let length = try buffer.throwingReadUB4()
                if length > 0 {
                    buffer.skipUB8()  // size (unused)
                    buffer.skipUB4()  // chunk size (unused)
                    switch buffer.readOracleSlice() {
                    case .some(let slice):
                        columnValue = slice
                    case .none:
                        throw MissingDataDecodingError.Trigger()
                    }
                    if !buffer.skipRawBytesChunked() {  // LOB locator (unused)
                        throw MissingDataDecodingError.Trigger()
                    }
                } else {
                    columnValue = .init(bytes: [0])  // empty buffer
                }
            case .intNamed:
                let startIndex = buffer.readerIndex
                if try buffer.throwingReadUB4() > 0 {
                    if !buffer.skipRawBytesChunked() {  // type oid
                        throw MissingDataDecodingError.Trigger()
                    }
                }
                if try buffer.throwingReadUB4() > 0 {
                    if !buffer.skipRawBytesChunked() {  // oid
                        throw MissingDataDecodingError.Trigger()
                    }
                }
                if try buffer.throwingReadUB4() > 0 {
                    if !buffer.skipRawBytesChunked() {  // snapshot
                        throw MissingDataDecodingError.Trigger()
                    }
                }
                buffer.skipUB2()  // version
                let dataLength = try buffer.throwingReadUB4()
                buffer.skipUB2()  // flags
                if dataLength > 0 {
                    if !buffer.skipRawBytesChunked() {  // data
                        throw MissingDataDecodingError.Trigger()
                    }
                }
                let endIndex = buffer.readerIndex
                buffer.moveReaderIndex(to: startIndex)
                columnValue = ByteBuffer(integer: Constants.TNS_LONG_LENGTH_INDICATOR)
                let length = (endIndex - startIndex) + (MemoryLayout<UInt32>.size * 2)
                columnValue.reserveCapacity(minimumWritableBytes: length)
                try columnValue.writeLengthPrefixed(as: UInt32.self) {
                    $0.writeImmutableBuffer(buffer.readSlice(length: endIndex - startIndex)!)
                }
                columnValue.writeInteger(0, as: UInt32.self)  // chunk length of zero
            default:
                fatalError(
                    "\(String(reflecting: oracleType)) is not implemented, please file a bug report"
                )
            }

            if [.long, .longRAW].contains(oracleType) {
                buffer.skipSB4()  // null indicator
                buffer.skipUB4()  // return code
            }

            return columnValue
        }

        private static func processBindRow(
            from buffer: inout ByteBuffer,
            statementContext: StatementContext,
            capabilities: Capabilities
        ) throws -> [ColumnStorage] {
            let outBinds = statementContext.statement.binds.metadata.compactMap(\.outContainer)
            guard !outBinds.isEmpty else { preconditionFailure() }
            var columns: [ColumnStorage] = []
            if statementContext.isReturning {
                for outBind in outBinds {
                    let rowCount = buffer.readUB4() ?? 0
                    if rowCount > 0 {
                        for _ in 0..<rowCount {
                            columns.append(
                                .data(
                                    try self.processBindData(
                                        from: &buffer,
                                        metadata: outBind.metadata.withLockedValue({ $0 }),
                                        capabilities: capabilities
                                    )))
                        }
                    } else {
                        // empty buffer
                        columns.append(.data(ByteBuffer(bytes: [0])))
                    }
                }
            } else {
                for outBind in outBinds {
                    columns.append(
                        .data(
                            try self.processBindData(
                                from: &buffer,
                                metadata: outBind.metadata.withLockedValue({ $0 }),
                                capabilities: capabilities
                            )))
                }
            }
            return columns
        }

        private static func processBindData(
            from buffer: inout ByteBuffer,
            metadata: OracleBindings.Metadata,
            capabilities: Capabilities
        ) throws -> ByteBuffer {
            let columnData = try self.processColumnData(
                from: &buffer,
                oracleType: metadata.dataType._oracleType,
                csfrm: metadata.dataType.csfrm,
                bufferSize: metadata.bufferSize,
                capabilities: capabilities
            )

            let actualBytesCount = buffer.readSB4() ?? 0
            if actualBytesCount < 0 && metadata.dataType._oracleType == .boolean {
                return ByteBuffer(bytes: [0])  // empty buffer
            } else if actualBytesCount != 0 && !columnData.oracleColumnIsEmpty {
                // TODO: throw this as error?
                preconditionFailure("column truncated, length: \(actualBytesCount)")
            }

            return columnData
        }
    }
}
