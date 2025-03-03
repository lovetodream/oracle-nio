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

#if compiler(>=6.0)
import NIOCore
import Testing

@testable import OracleNIO

@Suite struct OracleVectorTests {
    @Test func vectorBinary() {
        let vector1 = OracleVectorBinary()
        #expect(vector1 == [])
        let vector2: OracleVectorBinary = [1, 2, 3]
        #expect(vector2.count == 3)
        var vector3 = OracleVectorBinary([1, 2, 2])
        #expect(vector2 != vector3)
        #expect(vector3[2] == 2)
        vector3[2] = 3
        #expect(vector2 == vector3)
    }

    @Test func vectorInt8() {
        let vector1 = OracleVectorInt8()
        #expect(vector1 == [])
        let vector2: OracleVectorInt8 = [1, 2, 3]
        #expect(vector2.count == 3)
        var vector3 = OracleVectorInt8([1, 2, 2])
        #expect(vector2 != vector3)
        #expect(vector3[2] == 2)
        vector3[2] = 3
        #expect(vector2 == vector3)
    }

    @Test func vectorFloat32() {
        let vector1 = OracleVectorFloat32()
        #expect(vector1 == [])
        let vector2: OracleVectorFloat32 = [1.1, 2.2, 3.3]
        #expect(vector2.count == 3)
        var vector3 = OracleVectorFloat32([1.1, 2.2, 3.2])
        #expect(vector2 != vector3)
        #expect(vector3[2] == 3.2)
        vector3[2] = 3.3
        #expect(vector2 == vector3)
    }

    @Test func vectorFloat64() {
        let vector1 = OracleVectorFloat64()
        #expect(vector1 == [])
        let vector2: OracleVectorFloat64 = [1.1, 2.2, 3.3]
        #expect(vector2.count == 3)
        var vector3 = OracleVectorFloat64([1.1, 2.2, 3.2])
        #expect(vector2 != vector3)
        #expect(vector3[2] == 3.2)
        vector3[2] = 3.3
        #expect(vector2 == vector3)
    }

    @Test func decodingMalformedVectors() {
        // not a vector
        var buffer = ByteBuffer(bytes: [0])
        #expect(
            throws: OracleDecodingError.Code.typeMismatch,
            performing: { try OracleVectorInt8(from: &buffer, type: .raw, context: .default) }
        )
        #expect(
            throws: OracleDecodingError.Code.typeMismatch,
            performing: { try OracleVectorInt8(from: &buffer, type: .vector, context: .default) }
        )

        // invalid version
        buffer = ByteBuffer(bytes: [UInt8(Constants.TNS_VECTOR_MAGIC_BYTE), 42])
        #expect(
            throws: OracleDecodingError.Code.failure,
            performing: { try OracleVectorInt8(from: &buffer, type: .vector, context: .default) }
        )

        // wrong type
        buffer = ByteBuffer(bytes: [
            UInt8(Constants.TNS_VECTOR_MAGIC_BYTE),
            UInt8(Constants.TNS_VECTOR_VERSION_BASE),
            0, 0,  // flags
            VectorFormat.float64.rawValue,
            0, 0, 0, 0,  // elements
        ])
        #expect(
            throws: OracleDecodingError.Code.typeMismatch,
            performing: { try OracleVectorInt8(from: &buffer, type: .vector, context: .default) }
        )
    }
}
#endif
