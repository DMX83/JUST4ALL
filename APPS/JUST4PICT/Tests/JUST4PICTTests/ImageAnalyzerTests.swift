import XCTest
@testable import JUST4PICT

final class ImageAnalyzerTests: XCTestCase {
    func testInferSceneTypePrioritizesDocumentsWithDenseTextAndLowSaturation() {
        let analysis = PhotoAnalysis(
            averageLuminance: 0.84,
            averageSaturation: 0.06,
            isLowKey: false,
            isHighKey: true
        )

        let scene = ImageAnalyzer.inferSceneType(
            hasFaces: false,
            textObservationCount: 5,
            pixelSize: CGSize(width: 1400, height: 900),
            analysis: analysis,
            landscapeHint: false
        )

        XCTAssertEqual(scene, .document)
    }

    func testInferSceneTypeDetectsLowKeyPhotosBeforeGeneric() {
        let analysis = PhotoAnalysis(
            averageLuminance: 0.24,
            averageSaturation: 0.20,
            isLowKey: true,
            isHighKey: false
        )

        let scene = ImageAnalyzer.inferSceneType(
            hasFaces: false,
            textObservationCount: 0,
            pixelSize: CGSize(width: 1080, height: 1350),
            analysis: analysis,
            landscapeHint: false
        )

        XCTAssertEqual(scene, .darkPhoto)
    }

    func testInferSceneTypeStillPrefersLandscapeWhenVisualHintIsStrong() {
        let analysis = PhotoAnalysis(
            averageLuminance: 0.52,
            averageSaturation: 0.26,
            isLowKey: false,
            isHighKey: false
        )

        let scene = ImageAnalyzer.inferSceneType(
            hasFaces: false,
            textObservationCount: 0,
            pixelSize: CGSize(width: 1600, height: 900),
            analysis: analysis,
            landscapeHint: true
        )

        XCTAssertEqual(scene, .landscape)
    }
}
