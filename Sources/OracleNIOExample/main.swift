import OracleNIO
import Foundation

func env(_ name: String) -> String? {
    ProcessInfo.processInfo.environment[name]
}

var logger = Logger(label: "com.lovetodream.oraclenio")
logger.logLevel = .trace
let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
let ipAddress = env("ORA_IP_ADDRESS") ?? "192.168.1.24"
let port = (env("ORA_PORT").map(Int.init(_:)) ?? 1521) ?? 1521
let serviceName = env("ORA_SERVICE_NAME") ?? "XEPDB1"
let username = env("ORA_USERNAME") ?? "my_user"
let password = env("ORA_PASSWORD") ?? "my_passwor"
do {
    let connection = try OracleConnection.connect(
        using: .init(
            address: .init(ipAddress: ipAddress, port: port),
            serviceName: serviceName,
            username: username,
            password: password,
            autocommit: true
        ),
        logger: logger,
        on: group.next()
    ).wait()
//    try connection.query("select sysdate from dual")
//    try connection.query("insert into \"test\" (\"value\") values ('\(UUID().uuidString)')")
//    try connection.query("update \"test\" set \"value\" = '\(UUID().uuidString)'")
    try connection.query("delete from \"test\"")
    DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
        try! connection.close().wait()
    }
} catch {
    print(error)
}

RunLoop.main.run()
