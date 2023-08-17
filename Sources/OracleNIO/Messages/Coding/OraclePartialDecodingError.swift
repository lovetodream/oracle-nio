struct OraclePartialDecodingError: Error {
    /// A textual description of the error.
    let description: String

    /// The file this error was thrown in.
    let file: String

    /// The line in ``file`` this error was thrown in.
    let line: Int

    static func expectedAtLeastNRemainingBytes(
        _ expected: Int, actual: Int,
        file: String = #fileID, line: Int = #line
    ) -> Self {
        OraclePartialDecodingError(
            description: "Expected at least '\(expected)' remaining bytes. But found \(actual).",
            file: file, line: line
        )
    }

    static func fieldNotDecodable(
        type: Any.Type, file: String = #fileID, line: Int = #line
    ) -> Self {
        OraclePartialDecodingError(description: "Could not read '\(type)' from ByteBuffer.", file: file, line: line)
    }

    static func unsupportedDataType(
        type: DataType.Value, file: String = #fileID, line: Int = #line
    ) -> Self {
        OraclePartialDecodingError(
            description: "Could not process unsupported data type '\(type)'.",
            file: file, line: line
        )
    }
}
