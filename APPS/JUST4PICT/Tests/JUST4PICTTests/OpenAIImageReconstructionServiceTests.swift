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
}
