import NIOCore

public struct OracleQueryResult {
    public let metadata: OracleQueryMetadata
    public let rows: [OracleRow]
}

extension OracleQueryResult: Collection {
    public typealias Index = Int
    public typealias Element = OracleRow

    public var startIndex: Int { self.rows.startIndex }
    public var endIndex: Int { self.rows.endIndex }

    public subscript(position: Int) -> OracleRow {
        self.rows[position]
    }

    public func index(after i: Int) -> Int {
        self.rows.index(after: i)
    }
}

public struct OracleQueryMetadata { }
