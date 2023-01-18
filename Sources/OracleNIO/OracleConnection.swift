public class OracleConnection {
    var capabilities = Capabilities()

    public init() {}

    func createMessage<T: Message>() -> T {
        T.initialize(from: self)
    }
}
