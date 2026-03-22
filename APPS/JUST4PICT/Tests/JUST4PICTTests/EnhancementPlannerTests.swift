import XCTest
@testable import JUST4PICT

final class EnhancementPlannerTests: XCTestCase {
    func testResolveUsesRecipeFormatQualityAndUpscale() {
        let recommendation = AIImageRecommendation(
            preset: .landscape,
            quality: 0.88,
            reason: "Mejorar detalle y rango dinamico",
            hdPrompt: "prompt",
            tuning: AIEnhancementTuning(
                shadowAmount: 0.30,
                highlightAmount: 0.85,
                vibrance: 0.12,
                sharpen: 0.18,
                sharpenRadius: 0.45,
                contrast: 1.01,
                saturation: 1.02,
                exposureEV: 0.02
            ),
            recipe: EnhancementRecipe(
                scene: "landscape",
                objective: "Mantener naturalidad",
                preset: "Paisaje",
                exportFormat: "PNG",
                exportQuality: 0.93,
                tuning: AIEnhancementTuning(
                    shadowAmount: 0.30,
                    highlightAmount: 0.85,
                    vibrance: 0.12,
                    sharpen: 0.18,
                    sharpenRadius: 0.45,
                    contrast: 1.01,
                    saturation: 1.02,
                    exposureEV: 0.02
                ),
                upscale: AIUpscaleDecision(enabled: true, targetLongSide: 2400),
                faceRestore: nil
            ),
            rawContent: "{}"
        )

        let resolution = EnhancementPlanner.resolve(
            recommendation: recommendation,
            basePreset: .auto,
            baseFormat: .jpg,
            baseQuality: 0.8
        )

        XCTAssertEqual(resolution.preset, .landscape)
        XCTAssertEqual(resolution.format, .png)
        XCTAssertEqual(resolution.quality, OutputFormat.preferredQualityDefault)
        XCTAssertEqual(resolution.upscaleTargetLongSide, 2400)
        XCTAssertNil(resolution.faceRestoreStrength)
        XCTAssertEqual(EnhancementPlanner.suggestedPreset(for: resolution), .landscape)
        XCTAssertFalse(resolution.usedFallback)
    }

    func testFallbackPlanPreservesBaseValues() {
        let resolution = EnhancementPlanner.fallbackPlan(
            fileName: "sample.jpg",
            width: 1200,
            height: 800,
            basePreset: .portrait,
            baseFormat: .png,
            baseQuality: 1.0
        )

        XCTAssertEqual(resolution.preset, .portrait)
        XCTAssertEqual(resolution.format, .png)
        XCTAssertEqual(resolution.quality, 1.0)
        XCTAssertNil(resolution.upscaleTargetLongSide)
        XCTAssertNil(resolution.faceRestoreStrength)
        XCTAssertTrue(resolution.usedFallback)
        XCTAssertNotNil(resolution.aiPrompt)
    }

    func testResolveUsesClampedFaceRestoreStrengthWhenEnabled() {
        let recommendation = AIImageRecommendation(
            preset: .portrait,
            quality: 0.9,
            reason: "Recuperar detalle facial",
            hdPrompt: "prompt",
            tuning: AIEnhancementTuning(
                shadowAmount: 0.30,
                highlightAmount: 0.82,
                vibrance: 0.10,
                sharpen: 0.17,
                sharpenRadius: 0.40,
                contrast: 1.0,
                saturation: 1.0,
                exposureEV: 0.01
            ),
            recipe: EnhancementRecipe(
                scene: "portrait",
                objective: "Recuperar rostro",
                preset: "Retrato",
                exportFormat: "PNG",
                exportQuality: 1.0,
                tuning: AIEnhancementTuning(
                    shadowAmount: 0.30,
                    highlightAmount: 0.82,
                    vibrance: 0.10,
                    sharpen: 0.17,
                    sharpenRadius: 0.40,
                    contrast: 1.0,
                    saturation: 1.0,
                    exposureEV: 0.01
                ),
                upscale: nil,
                faceRestore: AIFaceRestoreDecision(enabled: true, strength: 1.4)
            ),
            rawContent: "{}"
        )

        let resolution = EnhancementPlanner.resolve(
            recommendation: recommendation,
            basePreset: .auto,
            baseFormat: .png,
            baseQuality: 1.0
        )

        XCTAssertEqual(resolution.faceRestoreStrength, 1.0)
        XCTAssertFalse(resolution.usedFallback)
    }

    func testRecipeMappedSceneSupportsIAOverrideValues() {
        XCTAssertEqual(makeRecipe(scene: "portrait").mappedScene, .portrait)
        XCTAssertEqual(makeRecipe(scene: "document").mappedScene, .document)
        XCTAssertEqual(makeRecipe(scene: "landscape").mappedScene, .landscape)
        XCTAssertEqual(makeRecipe(scene: "product").mappedScene, .ecommerce)
        XCTAssertEqual(makeRecipe(scene: "dark photo").mappedScene, .darkPhoto)
        XCTAssertEqual(makeRecipe(scene: "generic").mappedScene, .generic)
        XCTAssertNil(makeRecipe(scene: "unknown").mappedScene)
    }

    private func makeRecipe(scene: String) -> EnhancementRecipe {
        EnhancementRecipe(
            scene: scene,
            objective: "Objetivo",
            preset: "Auto",
            exportFormat: "PNG",
            exportQuality: 1.0,
            tuning: AIEnhancementTuning(
                shadowAmount: 0.30,
                highlightAmount: 0.82,
                vibrance: 0.10,
                sharpen: 0.17,
                sharpenRadius: 0.40,
                contrast: 1.0,
                saturation: 1.0,
                exposureEV: 0.01
            ),
            upscale: nil,
            faceRestore: nil
        )
    }
}
