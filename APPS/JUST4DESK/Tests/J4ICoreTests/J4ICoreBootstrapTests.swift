import XCTest
@testable import J4ICore

final class J4ICoreBootstrapTests: XCTestCase {
    func testBootstrapMetadataIsPopulated() {
        XCTAssertEqual(J4ICoreBootstrap.moduleName, "J4ICore")
        XCTAssertFalse(J4ICoreBootstrap.version.isEmpty)
    }
}
