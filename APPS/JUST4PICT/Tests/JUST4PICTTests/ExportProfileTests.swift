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

    func testEcommerceProfilePrefersLargerTargetForEcommercePreset() {
        XCTAssertEqual(ExportProfile.ecommerce.targetLongSide(for: .ecommerce), 2200)
        XCTAssertEqual(ExportProfile.ecommerce.targetLongSide(for: .portrait), 2000)
    }
}
