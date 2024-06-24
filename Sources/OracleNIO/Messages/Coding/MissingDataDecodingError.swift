struct MissingDataDecodingError: Error {
    let decodedMessages: TinySequence<OracleBackendMessage>
    let resetToReaderIndex: Int

    struct Trigger: Error {}
}
