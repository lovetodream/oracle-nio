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

    init(
        rba: UInt32,
        partitionID: UInt16,
        blockNumber: UInt32,
        slotNumber: UInt16
    ) {
        self.description = Self.makeDescription(
            rba: rba,
            partitionID: partitionID,
            blockNumber: blockNumber,
            slotNumber: slotNumber
        )
    }

    private static func makeDescription(
        rba: UInt32,
        partitionID: UInt16,
        blockNumber: UInt32,
        slotNumber: UInt16
    ) -> String {
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
            return String(bytes: bytes, encoding: .utf8) ?? ""
        }
        return ""
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
    public init<JSONDecoder: OracleJSONDecoder>(
        from buffer: inout ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext<JSONDecoder>
    ) throws {
        switch type {
        case .rowID:
            let rba = try buffer.throwingReadUB4()
            let partitionID = try buffer.throwingReadUB2()
            buffer.moveReaderIndex(forwardBy: 1)
            let blockNumber = try buffer.throwingReadUB4()
            let slotNumber = try buffer.throwingReadUB2()
            self = RowID(
                rba: rba,
                partitionID: partitionID,
                blockNumber: blockNumber,
                slotNumber: slotNumber
            )
        default:
            throw OracleDecodingError.Code.typeMismatch
        }
    }
}

extension RowID: OracleEncodable {
    public var oracleType: OracleDataType { .rowID }

    public func encode<JSONEncoder: OracleJSONEncoder>(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext<JSONEncoder>
    ) {
        buffer.writeString(self.description)
    }
}
