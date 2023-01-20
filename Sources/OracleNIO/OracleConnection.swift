public class OracleConnection {
    var capabilities = Capabilities()

    public init() {}

    func createMessage<T: TNSRequest>() -> T {
        T.initialize(from: self)
    }
}
