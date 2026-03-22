import XCTest
import CoreGraphics
@testable import JUST4PICT

final class RescueRecommendationTests: XCTestCase {
    func testRecommendsReconstructAIForExtremePortraitMiniature() {
        let recommendation = RescueRecommendationEngine.recommend(
            pixelSize: CGSize(width: 420, height: 560),
            scene: .portrait,
            fileSizeBytes: 38_000
        )

        XCTAssertEqual(recommendation, .reconstructAI)
    }

    func testRecommendsRealESRGANForSmallNonPortraitImage() {
        let recommendation = RescueRecommendationEngine.recommend(
            pixelSize: CGSize(width: 960, height: 1280),
            scene: .generic,
            fileSizeBytes: 180_000
        )

        XCTAssertEqual(recommendation, .realESRGAN)
    }

    func testKeepsProForPortraitWhenImageIsNotExtreme() {
        let recommendation = RescueRecommendationEngine.recommend(
            pixelSize: CGSize(width: 1400, height: 1800),
            scene: .portrait,
            fileSizeBytes: 420_000
        )

        XCTAssertEqual(recommendation, .pro)
    }

    func testRecommendsReconstructAIForTinyCompressedNonPortrait() {
        let recommendation = RescueRecommendationEngine.recommend(
            pixelSize: CGSize(width: 640, height: 640),
            scene: .generic,
            fileSizeBytes: 22_000
        )

        XCTAssertEqual(recommendation, .reconstructAI)
    }
}
