import OracleNIO
import Foundation

var logger = Logger(label: "com.lovetodream.oraclenio")
logger.logLevel = .trace
let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
do {
    _ = try OracleConnection.connect(to: .init(ipAddress: "192.168.1.22", port: 1521), logger: logger, on: group.next()).wait()
} catch {
    print(error)
}

RunLoop.main.run()
