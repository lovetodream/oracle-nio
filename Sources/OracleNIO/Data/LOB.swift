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

import NIOConcurrencyHelpers
import NIOCore

/// A LOB holds a reference to CLOB/BLOB data on an Oracle connection.
///
/// ## Reading data
///
/// Reading LOBs needs to be explicitly enabled by setting ``StatementOptions/fetchLOBs`` to
/// `true`. It is useful to retrieve huge amounts of data from a database.
///
/// - Note: Prefer using `Data` or `ByteBuffer` for reading and writing LOBs
///         less than 1 GB as they are more efficient. This is the behaviour if
///         ``StatementOptions/fetchLOBs`` is set to `false`.
///
/// ```swift
/// let queryOptions = StatementOptions(fetchLOBs: true)
/// let rows = try await connection
///     .execute("SELECT my_blob FROM my_table", options: queryOptions)
/// for try await (lob) in rows.decode(LOB.self) {
///     for try await chunk in lob.readChunks(on: connection) {
///         // do something with the buffer
///     }
/// }
/// ```
public final class LOB: Sendable {
    /// The total size of the data in the LOB.
    ///
    /// Bytes for BLOBs and USC-2 code points for CLOBs.
    /// USC-2 code points are equivalent to characters for all but supplemental characters.
    public let size: UInt64
    /// Reading and writing to the LOB in chunks of multiples of this size will improve performance.
    public let chunkSize: UInt32

    let locator: NIOLockedValueBox<[UInt8]>
    private let hasMetadata: Bool

    public let dbType: OracleDataType

    init(
        size: UInt64,
        chunkSize: UInt32,
        locator: [UInt8],
        hasMetadata: Bool,
        dbType: OracleDataType
    ) {
        self.size = size
        self.chunkSize = chunkSize
        self.locator = .init(locator)
        self.hasMetadata = hasMetadata
        self.dbType = dbType
    }

    static func create(dbType: OracleDataType, locator: [UInt8]?) -> Self {
        if let locator {
            return self.init(
                size: 0,
                chunkSize: 0,
                locator: locator,
                hasMetadata: false,
                dbType: dbType
            )
        } else {
            let locator = [UInt8](repeating: 0, count: 40)
            let lob = self.init(
                size: 0,
                chunkSize: 0,
                locator: locator,
                hasMetadata: false,
                dbType: dbType
            )
            // TODO: create temp lob on db
            return lob
        }
    }

    func encoding() -> String {
        let locator = self.locator.withLockedValue { $0 }
        if dbType.csfrm == Constants.TNS_CS_NCHAR
            || (locator.count >= Constants.TNS_LOB_LOCATOR_OFFSET_FLAG_3
                && (locator[Constants.TNS_LOB_LOCATOR_OFFSET_FLAG_3]
                    & Constants.TNS_LOB_LOCATOR_VAR_LENGTH_CHARSET) != 0)
        {
            return Constants.TNS_ENCODING_UTF16
        }
        return Constants.TNS_ENCODING_UTF8
    }

    func write(
        from buffer: ByteBuffer, offset: UInt64, on connection: OracleConnection
    ) {
        fatalError("TODO: write lob")
    }

    func _read(
        offset: UInt64 = 1,
        amount: UInt64? = nil,
        on connection: OracleConnection
    ) async throws -> ByteBuffer? {
        let promise = connection.eventLoop.makePromise(of: ByteBuffer?.self)
        connection.channel.write(
            OracleTask.lobOperation(
                .init(
                    sourceLOB: self,
                    sourceOffset: offset,
                    destinationLOB: nil,
                    destinationOffset: 0,
                    operation: .read,
                    sendAmount: true,
                    amount: amount ?? .init(self.chunkSize),
                    promise: promise
                )), promise: nil)
        return try await promise.futureResult.get()
    }

    func free(from cleanupContext: CleanupContext) {
        let locator = self.locator.withLockedValue { $0 }
        let flags1 = locator[Constants.TNS_LOB_LOCATOR_OFFSET_FLAG_1]
        let flags4 = locator[Constants.TNS_LOB_LOCATOR_OFFSET_FLAG_4]
        if flags1 & Constants.TNS_LOB_LOCATOR_FLAGS_ABSTRACT != 0
            || flags4 & Constants.TNS_LOB_LOCATOR_FLAGS_TEMP != 0
        {
            if cleanupContext.tempLOBsToClose == nil {
                cleanupContext.tempLOBsToClose = []
            }
            cleanupContext.tempLOBsToClose!.append(locator)
            cleanupContext.tempLOBsTotalSize += locator.count
        }
    }

}


// MARK: Public interfaces

extension LOB {
    /// Read chunks of data from the connection asynchronously.
    /// 
    /// - Parameters:
    ///   - chunkSize: The size of a single chunk of data read from the database.
    ///                If empty, ``chunkSize`` will be used.
    ///   - connection: The connection used the stream the buffer from.
    ///                 This has to be the same one the buffer was created on.
    /// - Returns: An async sequence used to iterate over
    ///            the chunks of data read from the connection.
    public func readChunks(
        ofSize chunkSize: UInt64? = nil,
        on connection: OracleConnection
    ) -> ReadSequence {
        ReadSequence(
            self,
            connection: connection,
            chunkSize: chunkSize ?? .init(self.chunkSize)
        )
    }

    /// An async sequence of `ByteBuffer`s used to stream LOB data from a connection.
    ///
    /// Created using ``LOB/readChunks(ofSize:on:)``.
    public struct ReadSequence: AsyncSequence {
        public typealias Element = ByteBuffer

        let base: LOB
        let connection: OracleConnection
        let chunkSize: UInt64

        init(_ base: LOB, connection: OracleConnection, chunkSize: UInt64) {
            self.base = base
            self.connection = connection
            self.chunkSize = chunkSize
        }

        public func makeAsyncIterator() -> AsyncIterator {
            AsyncIterator(
                base: self.base,
                connection: self.connection,
                chunkSize: self.chunkSize
            )
        }

        public struct AsyncIterator: AsyncIteratorProtocol {
            let base: LOB
            let connection: OracleConnection
            var offset: UInt64 = 1
            var chunkSize: UInt64

            public mutating func next() async throws -> ByteBuffer? {
                if self.offset >= self.base.size { return nil }
                guard
                    let chunk = try await self.base._read(
                        offset: self.offset,
                        amount: self.chunkSize,
                        on: self.connection
                    )
                else {
                    return nil
                }
                self.offset += UInt64(chunk.readableBytes)
                return chunk
            }
        }
    }
}

extension LOB: OracleEncodable {
    public var oracleType: OracleDataType { .blob }

    public func encode<JSONEncoder: OracleJSONEncoder>(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext<JSONEncoder>
    ) {
        preconditionFailure("This should not be called")
    }

    public func _encodeRaw<JSONEncoder: OracleJSONEncoder>(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext<JSONEncoder>
    ) {
        let locator = self.locator.withLockedValue { $0 }
        let length = locator.count
        buffer.writeUB4(UInt32(length))
        ByteBuffer(bytes: locator)._encodeRaw(into: &buffer, context: context)
    }
}

extension LOB: OracleDecodable {
    public convenience init<JSONDecoder: OracleJSONDecoder>(
        from buffer: inout ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext<JSONDecoder>
    ) throws {
        switch type {
        case .clob, .blob:
            let size = try buffer.throwingReadInteger(as: UInt64.self)
            let chunkSize = try buffer.throwingReadInteger(as: UInt32.self)
            let locator = try buffer.throwingReadOracleSpecificLengthPrefixedSlice()
            self.init(
                size: size,
                chunkSize: chunkSize,
                locator: Array(buffer: locator),
                hasMetadata: true,
                dbType: type
            )
        default:
            throw OracleDecodingError.Code.typeMismatch
        }
    }
}
