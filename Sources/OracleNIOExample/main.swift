import OracleNIO
import Foundation

func env(_ name: String) -> String? {
    ProcessInfo.processInfo.environment[name]
}

var logger = Logger(label: "com.lovetodream.oraclenio")
logger.logLevel = .trace
let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
let ipAddress = env("ORA_IP_ADDRESS") ?? "192.168.1.22"
let port = (env("ORA_PORT").map(Int.init(_:)) ?? 1521) ?? 1521
let serviceName = env("ORA_SERVICE_NAME") ?? "XEPDB1"
let username = env("ORA_USERNAME") ?? "my_user"
let password = env("ORA_PASSWORD") ?? "my_passwor"
do {
    _ = try OracleConnection.connect(
        using: .init(
            address: .init(ipAddress: ipAddress, port: port),
            serviceName: serviceName,
            username: username,
            password: password
        ),
        logger: logger,
        on: group.next()
    ).wait()
} catch {
    print(error)
}

RunLoop.main.run()
