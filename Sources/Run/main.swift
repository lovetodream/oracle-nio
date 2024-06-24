import OracleNIO
import NIOCore

var config: OracleConnection.Configuration = .init(host: "192.168.1.24", service: .serviceName("FREEPDB1"), username: "my_user", password: "my_passwor")
config.programName = "/Users/timozacherl/.pyenv/versions/3.11.1/bin/python"
config.connectionID = "jdN1SlI0RTnCdzTldXFE/Q=="
let connection = try await OracleConnection.connect(
    configuration: config,
    id: 3
)
var queryOptions = StatementOptions()
queryOptions.fetchLOBs = true
let rows = try await connection.execute(
    "SELECT id, content FROM test_simple_blob ORDER BY id",
    options: queryOptions
)
var index = 0
for try await (id, lob) in rows.decode((Int, LOB).self) {
    index += 1
    assert(index == id)
    var out = ByteBuffer()
    for try await var chunk in lob.read(on: connection) {
        out.writeBuffer(&chunk)
    }
    print(out)
    print(out.getString(at: 0, length: out.readableBytes)!)
}
assert(index == 1)
