import NIOCore
import NIOEmbedded

@testable import OracleNIO

extension OracleRowStream {

    convenience init(
        source: Source,
        eventLoop: any EventLoop = EmbeddedEventLoop()
    ) {
        self.init(
            source: source,
            eventLoop: eventLoop,
            logger: OracleConnection.noopLogger
        )
    }

}
