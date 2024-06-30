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
/// var offset = 1
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
    private let _size: UInt64
    private let _chunkSize: UInt32

    let locator: NIOLockedValueBox<[UInt8]>
    private let hasMetadata: Bool

    public let oracleType: OracleDataType

    init(
        size: UInt64,
        chunkSize: UInt32,
        locator: [UInt8],
        hasMetadata: Bool,
        oracleType: OracleDataType
    ) {
        self._size = size
        self._chunkSize = chunkSize
        self.locator = .init(locator)
        self.hasMetadata = hasMetadata
        self.oracleType = oracleType
    }

    func _read(
        offset: UInt64,
        amount: UInt64,
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
                    amount: amount,
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
        ofSize chunkSize: Int? = nil,
        on connection: OracleConnection
    ) -> ReadSequence {
        ReadSequence(
            self,
            connection: connection,
            chunkSize: UInt64(chunkSize ?? .init(self._chunkSize))
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
        at offset: Int = 1,
        on connection: OracleConnection
    ) async throws {
        let promise = connection.eventLoop.makePromise(of: ByteBuffer?.self)
        connection.channel.write(
            OracleTask.lobOperation(
                .init(
                    sourceLOB: self,
                    sourceOffset: UInt64(offset),
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
        to newSize: Int,
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
                    amount: UInt64(newSize),
                    promise: promise
                )), promise: nil)
        _ = try await promise.futureResult.get()
    }

    /// Create a temporary LOB on the given connection.
    ///
    /// The temporary LOB lives until the connection is closed or explicitly freed by calling
    /// ``free(on:)``.
    ///
    /// It can be inserted in a table at a later point as long as the connection lives.
    public static func create(
        _ oracleType: OracleDataType,
        on connection: OracleConnection
    ) async throws -> LOB {
        switch oracleType {
        case .blob, .clob, .nCLOB:
            let locator = [UInt8](repeating: 0, count: 40)
            let lob = self.init(
                size: 0,
                chunkSize: 0,
                locator: locator,
                hasMetadata: false,
                oracleType: oracleType
            )
            let promise = connection.eventLoop.makePromise(of: ByteBuffer?.self)
            connection.channel.write(
                OracleTask.lobOperation(
                    .init(
                        sourceLOB: lob,
                        sourceOffset: UInt64(oracleType.csfrm),
                        destinationLOB: nil,
                        destinationOffset: UInt64(oracleType._oracleType?.rawValue ?? 0),
                        operation: .createTemp,
                        sendAmount: true,
                        amount: Constants.TNS_DURATION_SESSION,
                        promise: promise
                    )), promise: nil)
            _ = try await promise.futureResult.get()
            return lob
        default:
            throw OracleSQLError.unsupportedDataType
        }
    }

    /// Frees/removes a temporary LOB from the given connection
    /// with the next round trip to the database.
    public func free(on connection: OracleConnection) async throws {
        let handler = try await connection.channel.pipeline
            .handler(type: OracleChannelHandler.self).get()
        self.free(from: handler.cleanupContext)
    }

    /// Retrieve the total size of the data in the LOB.
    ///
    /// Bytes for BLOBs and USC-2 code points for CLOBs.
    /// USC-2 code points are equivalent to characters for all but supplemental characters.
    public func size(on connection: OracleConnection) async throws -> Int {
        let promise = connection.eventLoop.makePromise(of: ByteBuffer?.self)
        let context = LOBOperationContext(
            sourceLOB: self,
            sourceOffset: 0,
            destinationLOB: nil,
            destinationOffset: 0,
            operation: .getLength,
            sendAmount: true,
            amount: 0,
            promise: promise
        )
        connection.channel.write(OracleTask.lobOperation(context), promise: nil)
        _ = try await promise.futureResult.get()
        return Int(context.fetchedAmount ?? 0)
    }

    /// The total size of the LOB data when it was first received from the database.
    ///
    /// It might have changed already. To get the up-to-date size use ``size(on:)``.
    public var estimatedSize: Int { Int(self._size) }


    /// Reading and writing to the LOB in chunks of multiples of this size will improve performance.
    public func chunkSize(on connection: OracleConnection) async throws -> Int {
        let promise = connection.eventLoop.makePromise(of: ByteBuffer?.self)
        let context = LOBOperationContext(
            sourceLOB: self,
            sourceOffset: 0,
            destinationLOB: nil,
            destinationOffset: 0,
            operation: .getChunkSize,
            sendAmount: true,
            amount: 0,
            promise: promise
        )
        connection.channel.write(OracleTask.lobOperation(context), promise: nil)
        _ = try await promise.futureResult.get()
        return Int(context.fetchedAmount ?? Int64(self._chunkSize))
    }

    /// Reading and writing to the LOB in chunks of multiples of this size will improve performance.
    ///
    /// This is the ideal chunk size at the time of fetching the LOB initially,
    /// it falls back to a sensible default if the underlying value is `0`.
    /// It might have changed in the meantime, to get the current chunk size use ``chunkSize(on:)``.
    public var estimatedChunkSize: Int {
        if self._chunkSize == 0 {
            8060
        } else {
            Int(self._chunkSize)
        }
    }
}

extension LOB: OracleEncodable {
    public func encode<JSONEncoder: OracleJSONEncoder>(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext<JSONEncoder>
    ) {
        let locator = self.locator.withLockedValue { $0 }
        let length = locator.count
        buffer.writeUB4(UInt32(length))
        ByteBuffer(bytes: locator)._encodeRaw(into: &buffer, context: context)
    }

    public func _encodeRaw<JSONEncoder: OracleJSONEncoder>(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext<JSONEncoder>
    ) {
        self.encode(into: &buffer, context: context)
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
                oracleType: type
            )
        default:
            throw OracleDecodingError.Code.typeMismatch
        }
    }
}
