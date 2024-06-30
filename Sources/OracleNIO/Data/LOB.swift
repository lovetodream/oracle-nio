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
/// LOBs can be read by using ``readChunks(ofSize:on:)`` and iterating
/// over the returned sequence.
///
/// ```swift
/// let queryOptions = StatementOptions(fetchLOBs: true)
/// let rows = try await connection
///     .execute("SELECT my_blob FROM my_table", options: queryOptions)
/// var lobs: [LOB] = []
/// for try await (lob) in rows.decode(LOB.self) {
///     lobs.append(lob)
/// }
/// for await lob in lobs {
///     for try await chunk in lob.readChunks(on: connection) {
///         // do something with the buffer
///     }
/// }
/// ```
///
///
/// ## Writing data
///
/// To fetch the LOB you want to write to, you'll need to enable ``StatementOptions/fetchLOBs``
/// for the statement you are fetching the LOB from. This is useful for writing huge amounts of data in a
/// streaming fashion.
///
/// - Note: Prefer using `Data` or `ByteBuffer` for reading and writing LOBs
///         less than 1 GB as they are more efficient. This is the behaviour if
///         ``StatementOptions/fetchLOBs`` is set to `false`.
///
/// Data is written in chunks using ``write(_:at:on:)``.
///
/// ```swift
/// var buffer = ByteBuffer(bytes: [0x1, 0x2, 0x3])
/// let lobRef = OracleRef(dataType: .blob, isReturnBind: true)
/// try await connection.execute(
///     """
///     INSERT INTO my_table (id, my_blob)
///     VALUES (1, empty_blob())
///     RETURNING my_blob INTO \(lobRef)
///     """,
///     options: .init(fetchLOBs: true)
/// )
/// let lob = try lobRef.decode(of: LOB.self)
/// var offset: UInt64 = 1
/// let chunkSize = 65536
/// while
///     buffer.readableBytes > 0,
///     let slice = buffer
///         .readSlice(length: min(chunkSize, buffer.readableBytes))
/// {
///     try await lob.write(slice, at: offset, on: connection)
///     offset += UInt64(slice.readableBytes)
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
    ///                 This has to be the same one the LOB reference was created on.
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
    
    /// Open the LOB for multiple ``write(_:at:on:)`` for improved performance.
    ///
    /// If this is not called before writing, every write operation opens and closes the LOB internally.
    ///
    /// Call ``close(on:)`` after you are done writing to the LOB.
    ///
    /// - Parameter connection: The connection used to open the LOB.
    ///                         This has to be the same one the LOB reference was created on.
    public func open(on connection: OracleConnection) async throws {
        let promise = connection.eventLoop.makePromise(of: ByteBuffer?.self)
        connection.channel.write(
            OracleTask.lobOperation(
                .init(
                    sourceLOB: self,
                    sourceOffset: 0,
                    destinationLOB: nil,
                    destinationOffset: 0,
                    operation: .open,
                    sendAmount: true,
                    amount: Constants.TNS_LOB_OPEN_READ_WRITE,
                    promise: promise
                )), promise: nil)
        _ = try await promise.futureResult.get()
    }
    /// Checks if the LOB is currently open for ``write(_:at:on:)`` operations.
    ///
    /// - Parameter connection: The connection used to check the status of the LOB on.
    ///                         This has to be the same one the LOB reference was created on.
    public func isOpen(on connection: OracleConnection) async throws -> Bool {
        let promise = connection.eventLoop.makePromise(of: ByteBuffer?.self)
        let context = LOBOperationContext(
            sourceLOB: self,
            sourceOffset: 0,
            destinationLOB: nil,
            destinationOffset: 0,
            operation: .isOpen,
            sendAmount: false,
            amount: 0,
            promise: promise
        )
        connection.channel.write(OracleTask.lobOperation(context), promise: nil)
        _ = try await promise.futureResult.get()
        return context.boolFlag ?? false
    }
    /// Closes the LOB if it is currently open for ``write(_:at:on:)`` operations.
    ///
    /// - Parameter connection: The connection used to close the LOB.
    ///                         This has to be the same one the LOB reference was created on.
    public func close(on connection: OracleConnection) async throws {
        let promise = connection.eventLoop.makePromise(of: ByteBuffer?.self)
        connection.channel.write(
            OracleTask.lobOperation(
                .init(
                    sourceLOB: self,
                    sourceOffset: 0,
                    destinationLOB: nil,
                    destinationOffset: 0,
                    operation: .close,
                    sendAmount: false,
                    amount: 0,
                    promise: promise
                )), promise: nil)
        _ = try await promise.futureResult.get()
    }

    /// Write data to the LOB starting on the specified offset.
    /// - Parameters:
    ///   - buffer: The chunk of data which should be written to the LOB.
    ///   - offset: The starting offset data will be written to. It is 1-base indexed.
    ///   - connection: The connection used to write to the LOB.
    ///                 This has to be the same one the LOB reference was created on.
    public func write(
        _ buffer: ByteBuffer,
        at offset: UInt64 = 1,
        on connection: OracleConnection
    ) async throws {
        let promise = connection.eventLoop.makePromise(of: ByteBuffer?.self)
        connection.channel.write(
            OracleTask.lobOperation(
                .init(
                    sourceLOB: self,
                    sourceOffset: offset,
                    destinationLOB: nil,
                    destinationOffset: 0,
                    operation: .write,
                    sendAmount: false,
                    amount: 0,
                    promise: promise,
                    data: buffer
                )), promise: nil)
        _ = try await promise.futureResult.get()
    }

    /// Trims the LOB to the provided size.
    /// - Parameters:
    ///   - newSize: Trims the LOB to this size.
    ///   - connection: The connection used to trim the LOB.
    ///                 This has to be the same one the LOB reference was created on.
    public func trim(
        to newSize: UInt64,
        on connection: OracleConnection
    ) async throws {
        let promise = connection.eventLoop.makePromise(of: ByteBuffer?.self)
        connection.channel.write(
            OracleTask.lobOperation(
                .init(
                    sourceLOB: self,
                    sourceOffset: 0,
                    destinationLOB: nil,
                    destinationOffset: 0,
                    operation: .trim,
                    sendAmount: true,
                    amount: newSize,
                    promise: promise
                )), promise: nil)
        _ = try await promise.futureResult.get()
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
