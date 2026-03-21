import Foundation
import CoreGraphics

struct AIRunResolution {
    let preset: EnhancementPreset
    let format: OutputFormat
    let quality: Double
    let upscaleTargetLongSide: CGFloat?
    let faceRestoreStrength: Double?
    let aiSuggestedPreset: String?
    let aiSuggestedQuality: Double?
    let aiReason: String?
    let aiPrompt: String?
    let aiTuning: AIEnhancementTuning?
    let recipe: EnhancementRecipe?
    let usedFallback: Bool
}

enum EnhancementPlanner {
    static func fallbackPlan(
        fileName: String,
        width: Int,
        height: Int,
        basePreset: EnhancementPreset,
        baseFormat: OutputFormat,
        baseQuality: Double
    ) -> AIRunResolution {
        AIRunResolution(
            preset: basePreset,
            format: baseFormat,
            quality: baseQuality,
            upscaleTargetLongSide: nil,
            faceRestoreStrength: nil,
            aiSuggestedPreset: nil,
            aiSuggestedQuality: nil,
            aiReason: nil,
            aiPrompt: OpenAIImageAdvisor.defaultHDPrompt(
                fileName: fileName,
                width: width,
                height: height,
                currentPreset: basePreset,
                currentFormat: baseFormat
            ),
            aiTuning: nil,
            recipe: nil,
            usedFallback: true
        )
    }

    static func resolve(
        recommendation: AIImageRecommendation,
        basePreset: EnhancementPreset,
        baseFormat: OutputFormat,
        baseQuality: Double
    ) -> AIRunResolution {
        let resolvedPreset = recommendation.recipe?.mappedPreset
            ?? recommendation.preset
            ?? basePreset
        let resolvedFormat = recommendation.recipe?.mappedExportFormat ?? baseFormat
        let resolvedQuality = resolvedFormat.supportsLossyQuality
            ? min(max(recommendation.recipe?.exportQuality ?? recommendation.quality ?? baseQuality, 0.5), 1.0)
            : OutputFormat.preferredQualityDefault
        let resolvedReason = recommendation.recipe?.objective ?? recommendation.reason
        let resolvedFaceRestoreStrength: Double?
        if let faceRestore = recommendation.recipe?.faceRestore, faceRestore.enabled {
            resolvedFaceRestoreStrength = faceRestore.strength.map { min(max($0, 0.0), 1.0) } ?? 0.5
        } else {
            resolvedFaceRestoreStrength = nil
        }

        return AIRunResolution(
            preset: resolvedPreset,
            format: resolvedFormat,
            quality: resolvedQuality,
            upscaleTargetLongSide: recommendation.recipe?.upscaleTargetLongSide,
            faceRestoreStrength: resolvedFaceRestoreStrength,
            aiSuggestedPreset: recommendation.recipe?.preset ?? recommendation.preset?.rawValue,
            aiSuggestedQuality: resolvedFormat.supportsLossyQuality ? resolvedQuality : nil,
            aiReason: resolvedReason,
            aiPrompt: recommendation.hdPrompt,
            aiTuning: recommendation.tuning,
            recipe: recommendation.recipe,
            usedFallback: false
        )
    }

    static func suggestedPreset(for resolution: AIRunResolution) -> EnhancementPreset? {
        if let recipePreset = resolution.recipe?.mappedPreset {
            return recipePreset
        }

        guard let value = resolution.aiSuggestedPreset else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "auto":
            return .auto
        case "retrato", "portrait":
            return .portrait
        case "paisaje", "landscape":
            return .landscape
        case "documento", "document":
            return .document
        case "ecommerce", "e-commerce":
            return .ecommerce
        default:
            return nil
        }
    }
}
