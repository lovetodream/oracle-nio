import OracleNIO

protocol IntegrationTest {
    var connection: OracleConnection! { get set }
}
