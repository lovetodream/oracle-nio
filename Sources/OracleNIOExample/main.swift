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
    do {
//        try connection.query("select sysdate from dual") // SELECT
        try connection.query("select * from \"test\"")
        //    try connection.query("insert into \"test\" (\"value\") values ('\(UUID().uuidString)')") // INSERT
//        try connection.query("insert into \"test\" (\"value\") values (:1)", binds: [UUID().uuidString]) // INSERT
//        try connection.query("insert into \"test\" (\"value\") values (:1)", binds: ["1"]) // INSERT
//        try connection.query("insert into \"test\" (\"value\") values ('1')") // INSERT
        //    try connection.query("update \"test\" set \"value\" = '\(UUID().uuidString)'") // UPDATE
        //    try connection.query("delete from \"test\"") // DELETE
        //    try connection.query("begin insert into \"test\" (\"value\") values ('\(UUID().uuidString)'); end;") // PLSQL
        //    try connection.query("create table test2(value varchar2(250))") // CREATE TABLE
        //    try connection.query("alter table test2 add value2 varchar2(250)") // ALTER TABLE
        //    try connection.query("drop table test2") // DROP TABLE
    } catch {
        print(error)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
        try! connection.close().wait()
    }
} catch {
    print(error)
}

RunLoop.main.run()
