#if compiler(>=6.0)
import Testing

@testable import OracleNIO

@Suite struct ArrayKeyTests {
    @Test func testInitWithInteger() {
        let key = ArrayKey(intValue: 2)!
        #expect(key.stringValue == "Index 2")
    }

    @Test func testInitWithIndex() {
        let key = ArrayKey(index: 12)
        #expect(key.stringValue == "Index 12")
    }

    @Test func testEquatable() {
        #expect(ArrayKey(index: 3) == ArrayKey(intValue: 3))
    }
}
#endif
