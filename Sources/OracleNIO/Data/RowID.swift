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

public struct RowID: CustomStringConvertible, Sendable, Equatable, Hashable {
    public let description: String

    init(_ value: String) {
        self.description = value
    }

    init?(
        rba: UInt32,
        partitionID: UInt16,
        blockNumber: UInt32,
        slotNumber: UInt16
    ) {
        guard
            let value = Self.makeDescription(
                rba: rba,
                partitionID: partitionID,
                blockNumber: blockNumber,
                slotNumber: slotNumber
            )
        else { return nil }
        self.description = value
    }

    private static func makeDescription(
        rba: UInt32,
        partitionID: UInt16,
        blockNumber: UInt32,
        slotNumber: UInt16
    ) -> String? {
        if rba != 0 || partitionID != 0 || blockNumber != 0 || slotNumber != 0 {
            var bytes = [UInt8](
                repeating: 0, count: Constants.TNS_MAX_ROWID_LENGTH
            )
            var offset = 0
            offset = convertBase64(
                bytes: &bytes,
                value: Int(rba),
                size: 6,
                offset: offset
            )
            offset = convertBase64(
                bytes: &bytes,
                value: Int(partitionID),
                size: 3,
                offset: offset
            )
            offset = convertBase64(
                bytes: &bytes,
                value: Int(blockNumber),
                size: 6,
                offset: offset
            )
            offset = convertBase64(
                bytes: &bytes,
                value: Int(slotNumber),
                size: 3,
                offset: offset
            )
            return String(decoding: bytes, as: UTF8.self)
        }
        return nil
    }

    private static func convertBase64(
        bytes: inout [UInt8],
        value: Int,
        size: Int,
        offset: Int
    ) -> Int {
        var value = value
        for i in 0..<size {
            bytes[offset + size - i - 1] =
                Constants.TNS_BASE64_ALPHABET_ARRAY[value & 0x3f]
            value = value >> 6
        }
        return offset + size
    }
}

extension RowID: OracleDecodable {
    /// Since RowID is represented differently when received (either binary or b64 encoded string), we want to unify it here.
    init?(fromWire buffer: inout ByteBuffer) throws {
        let rba = try buffer.throwingReadUB4()
        let partitionID = try buffer.throwingReadUB2()
        buffer.moveReaderIndex(forwardBy: 1)
        let blockNumber = try buffer.throwingReadUB4()
        let slotNumber = try buffer.throwingReadUB2()
        self.init(
            rba: rba,
            partitionID: partitionID,
            blockNumber: blockNumber,
            slotNumber: slotNumber
        )
    }

    @inlinable
    public init(
        from buffer: inout ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext
    ) throws {
        switch type {
        case .rowID:
            guard let value = buffer.readString(length: buffer.readableBytes) else {
                throw OracleDecodingError.Code.missingData
            }
            self.description = value
        default:
            throw OracleDecodingError.Code.typeMismatch
        }
    }
}

extension RowID: OracleEncodable {
    @inlinable
    public static var defaultOracleType: OracleDataType { .rowID }

    @inlinable
    public func encode(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext
    ) {
        buffer.writeString(self.description)
    }
}
