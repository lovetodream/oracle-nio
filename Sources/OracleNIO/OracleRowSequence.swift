import NIOCore
import NIOConcurrencyHelpers

/// An async sequence of ``OracleRow``'s
///
/// - Note: This is a struct to allow us to move to a move only type easily once they become available.
public struct OracleRowSequence: AsyncSequence {
    public typealias Element = OracleRow

    typealias BackingSequence = NIOThrowingAsyncSequenceProducer
        <DataRow, Error, AdaptiveRowBuffer, OracleRowStream>

    let backing: BackingSequence
    let lookupTable: [String: Int]
    let columns: [DescribeInfo.Column]

    init(
        _ backing: BackingSequence,
        lookupTable: [String: Int],
        columns: [DescribeInfo.Column]
    ) {
        self.backing = backing
        self.lookupTable = lookupTable
        self.columns = columns
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(
            backing: self.backing.makeAsyncIterator(),
            lookupTable: self.lookupTable,
            columns: self.columns
        )
    }
}

extension OracleRowSequence {
    public struct AsyncIterator: AsyncIteratorProtocol {
        public typealias Element = OracleRow

        let backing: BackingSequence.AsyncIterator

        let lookupTable: [String: Int]
        let columns: [DescribeInfo.Column]

        init(
            backing: BackingSequence.AsyncIterator,
            lookupTable: [String: Int],
            columns: [DescribeInfo.Column]
        ) {
            self.backing = backing
            self.lookupTable = lookupTable
            self.columns = columns
        }

        public mutating func next() async throws -> OracleRow? {
            guard let dataRow = try await self.backing.next() else {
                return nil
            }
            return OracleRow(
                lookupTable: self.lookupTable,
                data: dataRow,
                columns: self.columns
            )
        }
    }
}

extension OracleRowSequence {
    public func collect() async throws -> [OracleRow] {
        var result = [OracleRow]()
        for try await row in self {
            result.append(row)
        }
        return result
    }
}

struct AdaptiveRowBuffer: NIOAsyncSequenceProducerBackPressureStrategy {
    static let defaultBufferTarget = 256
    static let defaultBufferMinimum = 1
    static let defaultBufferMaximum = 16384

    let minimum: Int
    let maximum: Int

    private var target: Int
    private var canShrink: Bool = false

    init(minimum: Int, maximum: Int, target: Int) {
        precondition(minimum <= target && target <= maximum)
        self.minimum = minimum
        self.maximum = maximum
        self.target = target
    }

    init() {
        self.init(
            minimum: Self.defaultBufferMinimum,
            maximum: Self.defaultBufferMaximum,
            target: Self.defaultBufferTarget
        )
    }

    mutating func didYield(bufferDepth: Int) -> Bool {
        if 
            bufferDepth > self.target,
            self.canShrink, 
            self.target > self.minimum
        {
            self.target &>>= 1
        }
        self.canShrink = true

        return false // bufferDepth < self.target
    }

    mutating func didConsume(bufferDepth: Int) -> Bool {
        // if the buffer is drained now, we should double our target size
        if bufferDepth == 0, self.target < self.maximum {
            self.target = self.target * 2
            self.canShrink = false
        }

        return bufferDepth < self.target
    }
}
