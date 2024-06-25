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

/// A `Sequence` that does not heap allocate, if it only carries a few elements.
@usableFromInline
struct TinySequence<Element>: Sequence {
    @usableFromInline
    enum Base {
        case none(reserveCapacity: Int)
        case one(Element, reserveCapacity: Int)
        case two(Element, Element, reserveCapacity: Int)
        case n([Element])
    }

    @usableFromInline
    private(set) var base: Base

    @inlinable
    init() {
        self.base = .none(reserveCapacity: 0)
    }

    @inlinable
    init(element: Element) {
        self.base = .one(element, reserveCapacity: 1)
    }

    @inlinable
    init(_ collection: some Collection<Element>) {
        switch collection.count {
        case 0:
            self.base = .none(reserveCapacity: 0)
        case 1:
            self.base = .one(collection.first!, reserveCapacity: 0)
        case 2:
            self.base = .two(
                collection.first!,
                collection[collection.index(after: collection.startIndex)],
                reserveCapacity: 0
            )
        default:
            if let collection = collection as? [Element] {
                self.base = .n(collection)
            } else {
                self.base = .n(Array(collection))
            }
        }
    }

    @usableFromInline
    subscript(index: Int) -> Element {
        get {
            switch self.base {
            case .none:
                fatalError("Index out of range")
            case .one(let element, _):
                guard index == 0 else {
                    fatalError("Index out of range")
                }
                return element
            case .two(let element, let element2, _):
                switch index {
                case 0:
                    return element
                case 1:
                    return element2
                default:
                    fatalError("Index out of range")
                }
            case .n(let array):
                return array[index]
            }
        }
        set(newValue) {
            switch self.base {
            case .none:
                fatalError("Index out of range")
            case .one(_, let reserveCapacity):
                guard index == 0 else {
                    fatalError("Index out of range")
                }
                self.base = .one(newValue, reserveCapacity: reserveCapacity)
            case .two(let element, let element2, let reserveCapacity):
                switch index {
                case 0:
                    self.base = .two(newValue, element2, reserveCapacity: reserveCapacity)
                case 1:
                    self.base = .two(element, newValue, reserveCapacity: reserveCapacity)
                default:
                    fatalError("Index out of range")
                }
            case .n(var existing):
                self.base = .none(reserveCapacity: 0)  // prevent CoW
                existing[index] = newValue
                self.base = .n(existing)
            }
        }
    }

    @usableFromInline
    var count: Int {
        switch self.base {
        case .none:
            return 0
        case .one:
            return 1
        case .two:
            return 2
        case .n(let array):
            return array.count
        }
    }

    @inlinable
    var first: Element? {
        switch self.base {
        case .none:
            return nil
        case .one(let element, _):
            return element
        case .two(let first, _, _):
            return first
        case .n(let array):
            return array.first
        }
    }

    @usableFromInline
    var isEmpty: Bool {
        switch self.base {
        case .none:
            return true
        case .one, .two, .n:
            return false
        }
    }

    @inlinable
    mutating func reserveCapacity(_ minimumCapacity: Int) {
        switch self.base {
        case .none(let reservedCapacity):
            self.base = .none(reserveCapacity: Swift.max(reservedCapacity, minimumCapacity))
        case .one(let element, let reservedCapacity):
            self.base = .one(element, reserveCapacity: Swift.max(reservedCapacity, minimumCapacity))
        case .two(let first, let second, let reservedCapacity):
            self.base = .two(
                first, second, reserveCapacity: Swift.max(reservedCapacity, minimumCapacity))
        case .n(var array):
            self.base = .none(reserveCapacity: 0)  // prevent CoW
            array.reserveCapacity(minimumCapacity)
            self.base = .n(array)
        }
    }

    @inlinable
    mutating func append(_ element: Element) {
        switch self.base {
        case .none(let reserveCapacity):
            self.base = .one(element, reserveCapacity: reserveCapacity)
        case .one(let first, let reserveCapacity):
            self.base = .two(first, element, reserveCapacity: reserveCapacity)

        case .two(let first, let second, let reserveCapacity):
            var new = [Element]()
            new.reserveCapacity(Swift.max(4, reserveCapacity))
            new.append(first)
            new.append(second)
            new.append(element)
            self.base = .n(new)

        case .n(var existing):
            self.base = .none(reserveCapacity: 0)  // prevent CoW
            existing.append(element)
            self.base = .n(existing)
        }
    }

    @inlinable
    func makeIterator() -> Iterator {
        Iterator(self)
    }

    @usableFromInline
    struct Iterator: IteratorProtocol {
        @usableFromInline private(set) var index: Int = 0
        @usableFromInline private(set) var backing: TinySequence<Element>

        @inlinable
        init(_ backing: TinySequence<Element>) {
            self.backing = backing
        }

        @inlinable
        mutating func next() -> Element? {
            switch self.backing.base {
            case .none:
                return nil
            case .one(let element, _):
                if self.index == 0 {
                    self.index += 1
                    return element
                }
                return nil

            case .two(let first, let second, _):
                defer { self.index += 1 }
                switch self.index {
                case 0:
                    return first
                case 1:
                    return second
                default:
                    return nil
                }

            case .n(let array):
                if self.index < array.endIndex {
                    defer { self.index += 1 }
                    return array[self.index]
                }
                return nil
            }
        }
    }
}

extension TinySequence: Equatable where Element: Equatable {}
extension TinySequence.Base: Equatable where Element: Equatable {
    @usableFromInline
    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none):
            true
        case (.one(let lhs, _), .one(let rhs, _)):
            lhs == rhs
        case (.two(let lhs1, let lhs2, _), .two(let rhs1, let rhs2, _)):
            lhs1 == rhs1 && lhs2 == rhs2
        case (.n(let lhs), .n(let rhs)):
            lhs == rhs
        default:
            false
        }
    }
}

extension TinySequence: Hashable where Element: Hashable {}
extension TinySequence.Base: Hashable where Element: Hashable {
    @usableFromInline
    func hash(into hasher: inout Hasher) {
        switch self {
        case .none: break
        case .one(let value, _):
            hasher.combine(value)
        case .two(let value1, let value2, _):
            hasher.combine(value1)
            hasher.combine(value2)
        case .n(let values):
            hasher.combine(values)
        }
    }
}

extension TinySequence: Sendable where Element: Sendable {}
extension TinySequence.Base: Sendable where Element: Sendable {}

extension TinySequence: ExpressibleByArrayLiteral {
    @inlinable
    init(arrayLiteral elements: Element...) {
        var iterator = elements.makeIterator()
        switch elements.count {
        case 0:
            self.base = .none(reserveCapacity: 0)
        case 1:
            self.base = .one(iterator.next()!, reserveCapacity: 0)
        case 2:
            self.base = .two(iterator.next()!, iterator.next()!, reserveCapacity: 0)
        default:
            self.base = .n(elements)
        }
    }
}
