import NIOCore

/// A representation of a cell value within a ``OracleRow`` and ``OracleRandomAccessRow``.
public struct OracleCell: Sendable, Equatable {
    /// The cell's value as raw bytes.
    public var bytes: ByteBuffer?
    /// The cell's data type. This is important metadata when decoding the cell.
    public var dataType: DataType.Value

    /// The cell's column name within the row.
    public var columnName: Int
    /// The cell's column index within the row.
    public var columnIndex: Int

    public init(bytes: ByteBuffer? = nil, dataType: DataType.Value, columnName: Int, columnIndex: Int) {
        self.bytes = bytes
        self.dataType = dataType
        self.columnName = columnName
        self.columnIndex = columnIndex
    }
}
