import XCTest
@testable import JUST4PICT

final class ExportProfileTests: XCTestCase {
    func testOriginalProfileDoesNotRequestResize() {
        XCTAssertNil(ExportProfile.original.targetLongSide(for: .auto))
    }

    func testWebProfileUsesSmallerTargetThanSocial() {
        let webTarget = ExportProfile.web.targetLongSide(for: .auto)
        let socialTarget = ExportProfile.social.targetLongSide(for: .auto)

        XCTAssertEqual(webTarget, 1600)
        XCTAssertEqual(socialTarget, 2048)
        XCTAssertLessThan(webTarget ?? 0, socialTarget ?? 0)
    }

    func testWebLiteProfileUsesSmallerTargetAndDefinesByteBudget() {
        let webLiteTarget = ExportProfile.webLite.targetLongSide(for: .auto)
        let webTarget = ExportProfile.web.targetLongSide(for: .auto)

        XCTAssertEqual(webLiteTarget, 1280)
        XCTAssertEqual(ExportProfile.webLite.targetByteBudget, 300_000)
        XCTAssertEqual(ExportProfile.webLite.minimumLossyQuality, 0.58)
        XCTAssertLessThan(webLiteTarget ?? 0, webTarget ?? 0)
    }

    func testEcommerceProfilePrefersLargerTargetForEcommercePreset() {
        XCTAssertEqual(ExportProfile.ecommerce.targetLongSide(for: .ecommerce), 2200)
        XCTAssertEqual(ExportProfile.ecommerce.targetLongSide(for: .portrait), 2000)
    }
}
