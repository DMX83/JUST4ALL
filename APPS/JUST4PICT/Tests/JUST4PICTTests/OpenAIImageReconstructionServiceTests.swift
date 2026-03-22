import XCTest
@testable import JUST4PICT

final class OpenAIImageReconstructionServiceTests: XCTestCase {
    func testRecommendedCanvasSizeUsesLandscapeCanvas() {
        let size = OpenAIImageReconstructionService.recommendedCanvasSize(
            for: CGSize(width: 1600, height: 900)
        )

        XCTAssertEqual(size, "1536x1024")
    }

    func testRecommendedCanvasSizeUsesPortraitCanvas() {
        let size = OpenAIImageReconstructionService.recommendedCanvasSize(
            for: CGSize(width: 900, height: 1600)
        )

        XCTAssertEqual(size, "1024x1536")
    }

    func testRecommendedCanvasSizeUsesSquareCanvasForBalancedImages() {
        let size = OpenAIImageReconstructionService.recommendedCanvasSize(
            for: CGSize(width: 1024, height: 1024)
        )

        XCTAssertEqual(size, "1024x1024")
    }

    func testDefaultPromptIsNotEmpty() {
        XCTAssertFalse(OpenAIImageReconstructionService.defaultPrompt().isEmpty)
    }

    func testEcommercePromptMentionsWhiteBackgroundAndBranding() {
        let prompt = OpenAIImageReconstructionService.defaultPrompt(for: .ecommerceCleanup)

        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("white background"))
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("branding"))
    }

    func testRecommendedIntentUsesEcommerceForEcommercePreset() {
        let intent = OpenAIImageReconstructionService.recommendedIntent(
            preset: .ecommerce,
            scene: nil
        )

        XCTAssertEqual(intent, .ecommerceCleanup)
    }

    func testRecommendedIntentUsesEcommerceForDetectedEcommerceScene() {
        let intent = OpenAIImageReconstructionService.recommendedIntent(
            preset: .auto,
            scene: .ecommerce
        )

        XCTAssertEqual(intent, .ecommerceCleanup)
    }

    func testRecommendedIntentKeepsGeneralForPortrait() {
        let intent = OpenAIImageReconstructionService.recommendedIntent(
            preset: .portrait,
            scene: .portrait
        )

        XCTAssertEqual(intent, .general)
    }
}
