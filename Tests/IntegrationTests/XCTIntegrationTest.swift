import OracleNIO
import XCTest

class XCTIntegrationTest: XCTestCase, IntegrationTest {
    var connection: OracleConnection!

    override func setUp() async throws {
        try await super.setUp()
        if env("SMOKE_TEST_ONLY") == "1" {
            throw XCTSkip("Skipping... running only smoke test suite")
        }
        XCTAssertTrue(isLoggingConfigured)
        self.connection = try await OracleConnection.test()
    }

    override func tearDown() async throws {
        try await self.connection.close()
        try await super.tearDown()
    }
}
