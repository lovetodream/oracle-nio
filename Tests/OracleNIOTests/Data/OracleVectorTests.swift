import OracleNIO
import XCTest

final class OracleVectorTests: XCTestCase {
    func testVectorInt8() {
        var vector1 = OracleVectorInt8()
        XCTAssertEqual(vector1, [])
        vector1.reserveLanes(3)
        XCTAssertEqual(vector1, [0, 0, 0])
        let vector2: OracleVectorInt8 = [1, 2, 3]
        XCTAssertEqual(vector2.max(), 3)
        XCTAssertEqual(vector2.scalarCount, 3)
    }
}
