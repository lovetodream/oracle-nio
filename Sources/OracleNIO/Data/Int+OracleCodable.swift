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

// MARK: UInt8

extension UInt8: OracleDecodable {
    public init<JSONDecoder: OracleJSONDecoder>(
        from buffer: inout ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext<JSONDecoder>
    ) throws {
        switch type {
        case .char, .nChar, .raw, .longRAW, .long:
            guard
                buffer.readableBytes == 1,
                let value = buffer.readInteger(as: UInt8.self)
            else {
                throw OracleDecodingError.Code.failure
            }
            self = value
        case .number, .binaryInteger:
            self = try OracleNumeric.parseInteger(from: &buffer)
        default:
            throw OracleDecodingError.Code.typeMismatch
        }
    }
}

// MARK: Int8

extension Int8: OracleDecodable {
    public init<JSONDecoder: OracleJSONDecoder>(
        from buffer: inout ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext<JSONDecoder>
    ) throws {
        switch type {
        case .number, .binaryInteger:
            self = try OracleNumeric.parseInteger(from: &buffer)
        default:
            throw OracleDecodingError.Code.typeMismatch
        }
    }
}

// MARK: UInt16

extension UInt16: OracleDecodable {
    public init<JSONDecoder: OracleJSONDecoder>(
        from buffer: inout ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext<JSONDecoder>
    ) throws {
        switch type {
        case .number, .binaryInteger:
            self = try OracleNumeric.parseInteger(from: &buffer)
        default:
            throw OracleDecodingError.Code.typeMismatch
        }
    }
}

// MARK: Int16

extension Int16: OracleDecodable {
    public init<JSONDecoder: OracleJSONDecoder>(
        from buffer: inout ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext<JSONDecoder>
    ) throws {
        switch type {
        case .number, .binaryInteger:
            self = try OracleNumeric.parseInteger(from: &buffer)
        default:
            throw OracleDecodingError.Code.typeMismatch
        }
    }
}

// MARK: UInt32

extension UInt32: OracleDecodable {
    public init<JSONDecoder: OracleJSONDecoder>(
        from buffer: inout ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext<JSONDecoder>
    ) throws {
        switch type {
        case .number, .binaryInteger:
            self = try OracleNumeric.parseInteger(from: &buffer)
        default:
            throw OracleDecodingError.Code.typeMismatch
        }
    }
}

// MARK: Int32

extension Int32: OracleDecodable {
    public init<JSONDecoder: OracleJSONDecoder>(
        from buffer: inout ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext<JSONDecoder>
    ) throws {
        switch type {
        case .number, .binaryInteger:
            self = try OracleNumeric.parseInteger(from: &buffer)
        default:
            throw OracleDecodingError.Code.typeMismatch
        }
    }
}

// MARK: UInt64

extension UInt64: OracleDecodable {
    public init<JSONDecoder: OracleJSONDecoder>(
        from buffer: inout NIOCore.ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext<JSONDecoder>
    ) throws {
        switch type {
        case .number, .binaryInteger:
            self = try OracleNumeric.parseInteger(from: &buffer)
        default:
            throw OracleDecodingError.Code.typeMismatch
        }
    }
}

// MARK: Int64

extension Int64: OracleDecodable {
    public init<JSONDecoder: OracleJSONDecoder>(
        from buffer: inout NIOCore.ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext<JSONDecoder>
    ) throws {
        switch type {
        case .number, .binaryInteger:
            self = try OracleNumeric.parseInteger(from: &buffer)
        default:
            throw OracleDecodingError.Code.typeMismatch
        }
    }
}

// MARK: UInt

extension UInt: OracleDecodable {
    public init<JSONDecoder: OracleJSONDecoder>(
        from buffer: inout ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext<JSONDecoder>
    ) throws {
        switch type {
        case .number, .binaryInteger:
            self = try OracleNumeric.parseInteger(from: &buffer)
        default:
            throw OracleDecodingError.Code.typeMismatch
        }
    }
}

// MARK: Int

extension Int: OracleEncodable {
    public var oracleType: OracleDataType { .binaryInteger }

    public func encode<JSONEncoder: OracleJSONEncoder>(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext<JSONEncoder>
    ) {
        OracleNumeric.encodeNumeric(self, into: &buffer)
    }
}

extension Int: OracleDecodable {
    public init<JSONDecoder: OracleJSONDecoder>(
        from buffer: inout ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext<JSONDecoder>
    ) throws {
        switch type {
        case .number, .binaryInteger:
            self = try OracleNumeric.parseInteger(from: &buffer)
        default:
            throw OracleDecodingError.Code.typeMismatch
        }
    }
}
