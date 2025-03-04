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
    import Testing

    @testable import OracleNIO

    @Suite struct TinySequenceTests {
        @Test func countIsEmptyAndIterator() async {
            var sequence = TinySequence<Int>()
            #expect(sequence.count == 0)
            #expect(sequence.isEmpty == true)
            #expect(sequence.first == nil)
            #expect(Array(sequence) == [])
            sequence.append(1)
            #expect(sequence.count == 1)
            #expect(sequence.isEmpty == false)
            #expect(sequence.first == 1)
            #expect(Array(sequence) == [1])
            sequence.append(2)
            #expect(sequence.count == 2)
            #expect(sequence.isEmpty == false)
            #expect(sequence.first == 1)
            #expect(Array(sequence) == [1, 2])
            sequence.append(3)
            #expect(sequence.count == 3)
            #expect(sequence.isEmpty == false)
            #expect(sequence.first == 1)
            #expect(Array(sequence) == [1, 2, 3])
        }

        @Test func reserveCapacityIsForwarded() {
            var emptySequence = TinySequence<Int>()
            emptySequence.reserveCapacity(8)
            emptySequence.append(1)
            emptySequence.append(2)
            emptySequence.append(3)
            guard case .n(let array) = emptySequence.base else {
                Issue.record("Expected sequence to be backed by an array")
                return
            }
            #expect(array.capacity >= 8)

            var oneElemSequence = TinySequence<Int>(element: 1)
            oneElemSequence.reserveCapacity(8)
            oneElemSequence.append(2)
            oneElemSequence.append(3)
            guard case .n(let array) = oneElemSequence.base else {
                Issue.record("Expected sequence to be backed by an array")
                return
            }
            #expect(array.capacity >= 8)

            var twoElemSequence = TinySequence<Int>([1, 2])
            twoElemSequence.reserveCapacity(8)
            twoElemSequence.append(3)
            guard case .n(let array) = twoElemSequence.base else {
                Issue.record("Expected sequence to be backed by an array")
                return
            }
            #expect(array.capacity >= 8)

            var threeElemSequence = TinySequence<Int>([1, 2, 3])
            threeElemSequence.reserveCapacity(8)
            guard case .n(let array) = twoElemSequence.base else {
                Issue.record("Expected sequence to be backed by an array")
                return
            }
            #expect(array.capacity >= 8)
        }

        @Test func newSequenceSlowPath() {
            let sequence = TinySequence<UInt8>("AB".utf8)
            #expect(Array(sequence) == [UInt8(ascii: "A"), UInt8(ascii: "B")])
        }

        @Test func singleItem() {
            var sequence = TinySequence<UInt8>("A".utf8)
            #expect(sequence[0] == UInt8(ascii: "A"))
            #expect(Array(sequence) == [UInt8(ascii: "A")])
            sequence[0] = UInt8(ascii: "B")
            #expect(sequence[0] == UInt8(ascii: "B"))
            #expect(Array(sequence) == [UInt8(ascii: "B")])
        }

        @Test func twoItems() {
            var sequence = TinySequence<UInt8>("AB".ascii)
            #expect(sequence[0] == UInt8(ascii: "A"))
            #expect(sequence[1] == UInt8(ascii: "B"))
            #expect(Array(sequence) == [UInt8(ascii: "A"), UInt8(ascii: "B")])
            sequence[0] = UInt8(ascii: "C")
            sequence[1] = UInt8(ascii: "D")
            #expect(sequence[0] == UInt8(ascii: "C"))
            #expect(sequence[1] == UInt8(ascii: "D"))
            #expect(Array(sequence) == [UInt8(ascii: "C"), UInt8(ascii: "D")])
        }

        @Test func nItems() {
            var sequence = TinySequence<UInt8>("ABCD".ascii)
            #expect(sequence[0] == UInt8(ascii: "A"))
            #expect(sequence[1] == UInt8(ascii: "B"))
            #expect(sequence[2] == UInt8(ascii: "C"))
            #expect(sequence[3] == UInt8(ascii: "D"))
            #expect(
                Array(sequence) == [
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
            #expect(sequence[0] == UInt8(ascii: "F"))
            #expect(sequence[1] == UInt8(ascii: "G"))
            #expect(sequence[2] == UInt8(ascii: "H"))
            #expect(sequence[3] == UInt8(ascii: "I"))
            #expect(sequence[4] == UInt8(ascii: "J"))
        }

        @Test func emptyCollection() {
            let sequence = TinySequence<UInt8>("".utf8)
            #expect(sequence.isEmpty)
            #expect(sequence.count == 0)
            #expect(Array(sequence) == [])
        }

        @Test func customEquatableAndHashable() {
            // Equatable
            #expect(TinySequence<UInt8>() == [])
            #expect(TinySequence("A".utf8) == [UInt8(ascii: "A")])
            #expect(TinySequence("AB".utf8) == [UInt8(ascii: "A"), UInt8(ascii: "B")])
            #expect(TinySequence("ABC".utf8) == [UInt8(ascii: "A"), UInt8(ascii: "B"), UInt8(ascii: "C")])
            #expect(TinySequence("A".utf8) != [UInt8(ascii: "A"), UInt8(ascii: "B")])

            // Hashable
            #expect(TinySequence<UInt8>().hashValue == TinySequence<UInt8>().hashValue)
            #expect(TinySequence("A".utf8).hashValue == TinySequence("A".utf8).hashValue)
            #expect(TinySequence("AB".utf8).hashValue == TinySequence("AB".utf8).hashValue)
            #expect(TinySequence("ABC".utf8).hashValue == TinySequence("ABC".utf8).hashValue)
            #expect(TinySequence("A".utf8).hashValue != TinySequence("AB".utf8).hashValue)
        }
    }
#endif
