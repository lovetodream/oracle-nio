import XCTest
@testable import OracleNIO

final class OracleClientTests: XCTestCase {

    func testPool() async throws {
        let config = OracleConnection.Configuration(
            host: env("ORA_HOSTNAME") ?? "192.168.1.24",
            port: env("ORA_PORT").flatMap(Int.init) ?? 1521,
            service: .serviceName(env("ORA_SERVICE_NAME") ?? "XEPDB1"),
            username: env("ORA_USERNAME") ?? "my_user",
            password: env("ORA_PASSWORD") ?? "my_passwor"
        )
        let client = OracleClient(configuration: config, backgroundLogger: .oracleTest)
        await withThrowingTaskGroup(of: Void.self) { taskGroup in
            taskGroup.addTask {
                await client.run()
            }
        
            taskGroup.addTask {
                try await client.withConnection { connection in
                    do {
                        let rows = try await connection.query("SELECT 1, 'Timo', 23 FROM dual;", logger: .oracleTest)
                        for try await (userID, name, age) in rows.decode((Int, String, Int).self) {
                            XCTAssertEqual(userID, 1)
                            XCTAssertEqual(name, "Timo")
                            XCTAssertEqual(age, 23)
                        }
                    } catch {
                        XCTFail("Unexpected error: \(error)")
                    }
                }
            }
        }
    }

}
