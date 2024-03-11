import OracleNIO

// snippet.configuration
let configuration = OracleConnection.Configuration(
    host: "localhost",
    service: .serviceName("my_service_name"),
    username: "my_username",
    password: "my_password"
)
// snippet.end

// snippet.makeClient
let client = OracleClient(configuration: configuration)
// snippet.end

// snippet.run
await withTaskGroup(of: Void.self) { taskGroup in
    taskGroup.addTask {
        await client.run() // !important
    }

    // You can use the client while the `client.run()` method is not cancelled.

    // To shutdown the client, cancel its run method, by cancelling the taskGroup.
    taskGroup.cancelAll()
}
// snippet.end
