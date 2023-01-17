public class OracleConnection {
    public init() {}

    func createMessage<T: Message>() -> T {
        T.initialize(from: self)
    }
}
