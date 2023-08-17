/// An error representing a failure to decode a Oracle wire message to the Swift structure
/// ``OracleBackendMessage``.
///
/// If you encounter a `DecodingError` when using a trusted Oracle server please make sure to file an
/// issue at: [https://github.com/lovetodream/oracle-nio/issues](https://github.com/lovetodream/oracle-nio/issues).
struct OracleMessageDecodingError: Error {

}
