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

import XCTest

@testable import OracleNIO

final class TinySequenceTests: XCTestCase {
    func testCountIsEmptyAndIterator() async {
        var sequence = TinySequence<Int>()
        XCTAssertEqual(sequence.count, 0)
        XCTAssertEqual(sequence.isEmpty, true)
        XCTAssertEqual(sequence.first, nil)
        XCTAssertEqual(Array(sequence), [])
        sequence.append(1)
        XCTAssertEqual(sequence.count, 1)
        XCTAssertEqual(sequence.isEmpty, false)
        XCTAssertEqual(sequence.first, 1)
        XCTAssertEqual(Array(sequence), [1])
        sequence.append(2)
        XCTAssertEqual(sequence.count, 2)
        XCTAssertEqual(sequence.isEmpty, false)
        XCTAssertEqual(sequence.first, 1)
        XCTAssertEqual(Array(sequence), [1, 2])
        sequence.append(3)
        XCTAssertEqual(sequence.count, 3)
        XCTAssertEqual(sequence.isEmpty, false)
        XCTAssertEqual(sequence.first, 1)
        XCTAssertEqual(Array(sequence), [1, 2, 3])
    }

    func testReserveCapacityIsForwarded() {
        var emptySequence = TinySequence<Int>()
        emptySequence.reserveCapacity(8)
        emptySequence.append(1)
        emptySequence.append(2)
        emptySequence.append(3)
        guard case .n(let array) = emptySequence.base else {
            return XCTFail("Expected sequence to be backed by an array")
        }
        XCTAssertGreaterThanOrEqual(array.capacity, 8)

        var oneElemSequence = TinySequence<Int>(element: 1)
        oneElemSequence.reserveCapacity(8)
        oneElemSequence.append(2)
        oneElemSequence.append(3)
        guard case .n(let array) = oneElemSequence.base else {
            return XCTFail("Expected sequence to be backed by an array")
        }
        XCTAssertGreaterThanOrEqual(array.capacity, 8)

        var twoElemSequence = TinySequence<Int>([1, 2])
        twoElemSequence.reserveCapacity(8)
        twoElemSequence.append(3)
        guard case .n(let array) = twoElemSequence.base else {
            return XCTFail("Expected sequence to be backed by an array")
        }
        XCTAssertGreaterThanOrEqual(array.capacity, 8)

        var threeElemSequence = TinySequence<Int>([1, 2, 3])
        threeElemSequence.reserveCapacity(8)
        guard case .n(let array) = twoElemSequence.base else {
            return XCTFail("Expected sequence to be backed by an array")
        }
        XCTAssertGreaterThanOrEqual(array.capacity, 8)
    }

    func testNewSequenceSlowPath() {
        let sequence = TinySequence<UInt8>("AB".utf8)
        XCTAssertEqual(Array(sequence), [UInt8(ascii: "A"), UInt8(ascii: "B")])
    }

    func testSingleItem() {
        var sequence = TinySequence<UInt8>("A".utf8)
        XCTAssertEqual(sequence[0], UInt8(ascii: "A"))
        XCTAssertEqual(Array(sequence), [UInt8(ascii: "A")])
        sequence[0] = UInt8(ascii: "B")
        XCTAssertEqual(sequence[0], UInt8(ascii: "B"))
        XCTAssertEqual(Array(sequence), [UInt8(ascii: "B")])
    }

    func testTwoItems() {
        var sequence = TinySequence<UInt8>("AB".ascii)
        XCTAssertEqual(sequence[0], UInt8(ascii: "A"))
        XCTAssertEqual(sequence[1], UInt8(ascii: "B"))
        XCTAssertEqual(Array(sequence), [UInt8(ascii: "A"), UInt8(ascii: "B")])
        sequence[0] = UInt8(ascii: "C")
        sequence[1] = UInt8(ascii: "D")
        XCTAssertEqual(sequence[0], UInt8(ascii: "C"))
        XCTAssertEqual(sequence[1], UInt8(ascii: "D"))
        XCTAssertEqual(Array(sequence), [UInt8(ascii: "C"), UInt8(ascii: "D")])
    }

    func testNItems() {
        var sequence = TinySequence<UInt8>("ABCD".ascii)
        XCTAssertEqual(sequence[0], UInt8(ascii: "A"))
        XCTAssertEqual(sequence[1], UInt8(ascii: "B"))
        XCTAssertEqual(sequence[2], UInt8(ascii: "C"))
        XCTAssertEqual(sequence[3], UInt8(ascii: "D"))
        XCTAssertEqual(
            Array(sequence),
            [
                UInt8(ascii: "A"),
                UInt8(ascii: "B"),
                UInt8(ascii: "C"),
                UInt8(ascii: "D"),
            ])
        sequence[0] = UInt8(ascii: "F")
        sequence[1] = UInt8(ascii: "G")
        sequence[2] = UInt8(ascii: "H")
        sequence[3] = UInt8(ascii: "I")
        sequence.append(UInt8(ascii: "J"))
        XCTAssertEqual(sequence[0], UInt8(ascii: "F"))
        XCTAssertEqual(sequence[1], UInt8(ascii: "G"))
        XCTAssertEqual(sequence[2], UInt8(ascii: "H"))
        XCTAssertEqual(sequence[3], UInt8(ascii: "I"))
        XCTAssertEqual(sequence[4], UInt8(ascii: "J"))
    }

    func testEmptyCollection() {
        let sequence = TinySequence<UInt8>("".utf8)
        XCTAssertTrue(sequence.isEmpty)
        XCTAssertEqual(sequence.count, 0)
        XCTAssertEqual(Array(sequence), [])
    }

    func testCustomEquatableAndHashable() {
        // Equatable
        XCTAssertEqual(TinySequence<UInt8>(), [])
        XCTAssertEqual(TinySequence("A".utf8), [UInt8(ascii: "A")])
        XCTAssertEqual(
            TinySequence("AB".utf8),
            [UInt8(ascii: "A"), UInt8(ascii: "B")]
        )
        XCTAssertEqual(
            TinySequence("ABC".utf8),
            [UInt8(ascii: "A"), UInt8(ascii: "B"), UInt8(ascii: "C")]
        )
        XCTAssertNotEqual(
            TinySequence("A".utf8),
            [UInt8(ascii: "A"), UInt8(ascii: "B")]
        )

        // Hashable
        XCTAssertEqual(
            TinySequence<UInt8>().hashValue,
            TinySequence<UInt8>().hashValue
        )
        XCTAssertEqual(
            TinySequence("A".utf8).hashValue,
            TinySequence("A".utf8).hashValue
        )
        XCTAssertEqual(
            TinySequence("AB".utf8).hashValue,
            TinySequence("AB".utf8).hashValue
        )
        XCTAssertEqual(
            TinySequence("ABC".utf8).hashValue,
            TinySequence("ABC".utf8).hashValue
        )
        XCTAssertNotEqual(
            TinySequence("A".utf8).hashValue,
            TinySequence("AB".utf8).hashValue
        )
    }
}
