import XCTest
@testable import OracleNIO
import NIOCore

final class OracleCodableTests: XCTestCase {

    func testDecodeAnOptionalFromARow() {
        let row = OracleRow(
            lookupTable: ["id": 0, "name": 1],
            data: .makeTestDataRow(nil, "Hello world!"),
            columns: .init(
                repeating: .init(
                    name: "id",
                    dataType: .varchar,
                    dataTypeSize: 1,
                    precision: 1,
                    scale: 1,
                    bufferSize: 1,
                    nullsAllowed: true
                ), count: 2
            )
        )

        var result: (String?, String?)
        XCTAssertNoThrow(result = try row.decode((String?, String?).self, context: .default))
        XCTAssertNil(result.0)
        XCTAssertEqual(result.1, "Hello world!")
    }

}

extension DataRow: ExpressibleByArrayLiteral {
    public typealias ArrayLiteralElement = OracleThrowingEncodable

    public init(arrayLiteral elements: any OracleThrowingEncodable...) {
        var buffer = ByteBuffer()
        let encodingContext = OracleEncodingContext(jsonEncoder: JSONEncoder())
        elements.forEach { element in
            try! element.encodeRaw(into: &buffer, context: encodingContext)
        }
        self.init(columnCount: elements.count, bytes: buffer)
    }

    static func makeTestDataRow(_ encodables: (any OracleEncodable)?...) -> DataRow {
        var bytes = ByteBuffer()
        encodables.forEach { column in
            switch column {
            case .none:
                bytes.writeInteger(UInt8(0))
            case .some(var input):
                input.encode(into: &bytes, context: .default)
            }
        }

        return DataRow(columnCount: encodables.count, bytes: bytes)
    }
}
