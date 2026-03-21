import XCTest
@testable import JUST4PICT

final class OutputFormatTests: XCTestCase {
    func testFileExtensionsMatchExpectedValues() {
        XCTAssertEqual(OutputFormat.jpg.fileExtension, "jpg")
        XCTAssertEqual(OutputFormat.png.fileExtension, "png")
        XCTAssertEqual(OutputFormat.heic.fileExtension, "heic")
        XCTAssertEqual(OutputFormat.webp.fileExtension, "webp")
        XCTAssertEqual(OutputFormat.tiff.fileExtension, "tiff")
    }

    func testSupportsLossyQualityMatchesFormatCapabilities() {
        XCTAssertTrue(OutputFormat.jpg.supportsLossyQuality)
        XCTAssertTrue(OutputFormat.heic.supportsLossyQuality)
        XCTAssertTrue(OutputFormat.webp.supportsLossyQuality)
        XCTAssertFalse(OutputFormat.png.supportsLossyQuality)
        XCTAssertFalse(OutputFormat.tiff.supportsLossyQuality)
    }

    func testPreferredDefaultUsesHighestQualityFormat() {
        XCTAssertEqual(OutputFormat.preferredDefault, .png)
        XCTAssertEqual(OutputFormat.preferredQualityDefault, 1.0)
        XCTAssertEqual(OutputFormat.pickerOrder.first, .png)
    }
}
