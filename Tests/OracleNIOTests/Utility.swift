import OracleNIO

extension OracleConnection {
    static func address() throws -> SocketAddress {
        try .makeAddressResolvingHost(
            env("ORA_HOSTNAME") ?? "192.168.1.24",
            port: env("ORA_PORT").flatMap(Int.init) ?? 1521
        )
    }

    static func test(
        on eventLoop: EventLoop,
        logLevel: Logger.Level = Logger.getLogLevel()
    ) -> EventLoopFuture<OracleConnection> {
        var logger = Logger(label: "oracle.connection.test")
        logger.logLevel = logLevel

        do {
            let config = OracleConnection.Configuration(
                address: try Self.address(),
                serviceName: env("ORA_SERVICE_NAME") ?? "XEPDB1",
                username: env("ORA_USERNAME") ?? "my_user",
                password: env("ORA_PASSWORD") ?? "my_passwor"
            )

            return OracleConnection.connect(
                on: eventLoop, configuration: config, id: 0, logger: logger
            )
        } catch {
            return eventLoop.makeFailedFuture(error)
        }
    }
}

extension Logger {
    static var oracleTest: Logger {
        var logger = Logger(label: "oracle.test")
        logger.logLevel = self.getLogLevel()
        return logger
    }

    static func getLogLevel() -> Logger.Level {
        let ghActionsDebug = env("ACTIONS_STEP_DEBUG")
        if ghActionsDebug == "true" || ghActionsDebug == "TRUE" {
            return .trace
        }

        return env("LOG_LEVEL").flatMap {
            Logger.Level(rawValue: $0)
        } ?? .debug
    }
}

func env(_ name: String) -> String? {
    getenv(name).flatMap { String(cString: $0) }
}
