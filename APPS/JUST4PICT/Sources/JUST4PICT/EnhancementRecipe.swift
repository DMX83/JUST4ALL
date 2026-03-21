import Foundation
import CoreGraphics

struct AIEnhancementTuning: Codable, Hashable {
    let shadowAmount: Double
    let highlightAmount: Double
    let vibrance: Double
    let sharpen: Double
    let sharpenRadius: Double
    let contrast: Double
    let saturation: Double
    let exposureEV: Double

    func clamped() -> AIEnhancementTuning {
        AIEnhancementTuning(
            shadowAmount: min(max(shadowAmount, 0.20), 0.50),
            highlightAmount: min(max(highlightAmount, 0.70), 1.00),
            vibrance: min(max(vibrance, 0.05), 0.25),
            sharpen: min(max(sharpen, 0.10), 0.45),
            sharpenRadius: min(max(sharpenRadius, 0.30), 0.90),
            contrast: min(max(contrast, 0.94), 1.05),
            saturation: min(max(saturation, 0.95), 1.08),
            exposureEV: min(max(exposureEV, -0.15), 0.12)
        )
    }
}

struct AIUpscaleDecision: Codable, Hashable {
    let enabled: Bool
    let targetLongSide: Int?
}

struct AIFaceRestoreDecision: Codable, Hashable {
    let enabled: Bool
    let strength: Double?
}

struct EnhancementRecipe: Codable, Hashable {
    let scene: String
    let objective: String
    let preset: String
    let exportFormat: String
    let exportQuality: Double
    let tuning: AIEnhancementTuning
    let upscale: AIUpscaleDecision?
    let faceRestore: AIFaceRestoreDecision?

    func clamped() -> EnhancementRecipe {
        EnhancementRecipe(
            scene: scene,
            objective: objective.trimmingCharacters(in: .whitespacesAndNewlines),
            preset: preset,
            exportFormat: exportFormat,
            exportQuality: min(max(exportQuality, 0.92), 1.0),
            tuning: tuning.clamped(),
            upscale: upscale,
            faceRestore: faceRestore.map {
                AIFaceRestoreDecision(
                    enabled: $0.enabled,
                    strength: $0.strength.map { min(max($0, 0.0), 1.0) }
                )
            }
        )
    }
}

extension EnhancementRecipe {
    var mappedPreset: EnhancementPreset? {
        let normalized = preset.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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

    var mappedExportFormat: OutputFormat? {
        let normalized = exportFormat.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "png":
            return .png
        case "jpg", "jpeg":
            return .jpg
        case "heic":
            return .heic
        case "webp":
            return .webp
        case "tiff", "tif":
            return .tiff
        default:
            return nil
        }
    }

    var upscaleTargetLongSide: CGFloat? {
        guard let upscale, upscale.enabled else { return nil }
        guard let target = upscale.targetLongSide, target > 0 else { return nil }
        return CGFloat(target)
    }
}
