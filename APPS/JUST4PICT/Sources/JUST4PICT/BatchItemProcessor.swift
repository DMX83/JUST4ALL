import Foundation
import CoreGraphics

/// Dominio de batch: ejecución de un ítem del lote (PRO / IA / Reconstruir IA) fuera de la vista.
struct BatchItemJob {
    let inputURL: URL
    let outputURL: URL
    let mode: EnhancementMode
    let preset: EnhancementPreset
    let quality: Double
    let format: OutputFormat
    let exportProfile: ExportProfile
    let upscaleTargetLongSide: CGFloat?
    let faceRestoreStrength: Double?
    let sceneOverride: ImageEnhancer.SceneType?
    let aiPrompt: String?
    let aiTuning: AIEnhancementTuning?
}

struct BatchItemProcessor {
    let enhancer: ImageEnhancer
    let reconstruction: OpenAIImageReconstructionService

    func run(_ job: BatchItemJob) async throws {
        if job.mode == .ai {
            _ = resolvedAIPrompt(for: job.inputURL, preferredPrompt: job.aiPrompt)
        }

        if job.mode == .reconstructAI {
            let intent = reconstructionIntent(
                for: job.inputURL,
                preset: job.preset,
                sceneOverride: job.sceneOverride
            )
            try await reconstruction.reconstructImage(
                inputURL: job.inputURL,
                outputURL: job.outputURL,
                format: job.format,
                quality: job.quality,
                exportProfile: job.exportProfile,
                preset: job.preset,
                intent: intent
            )
            return
        }

        try await Task.detached(priority: .userInitiated) {
            try autoreleasepool {
                let worker = ImageEnhancer()
                try worker.enhance(
                    inputURL: job.inputURL,
                    outputURL: job.outputURL,
                    preset: job.preset,
                    quality: job.quality,
                    format: job.format,
                    exportProfile: job.exportProfile,
                    upscaleTargetLongSide: job.upscaleTargetLongSide,
                    faceRestoreStrength: job.faceRestoreStrength,
                    tuning: job.aiTuning,
                    sceneOverride: job.sceneOverride
                )
            }
        }.value
    }

    func resolvedAIPrompt(for inputURL: URL, preferredPrompt: String?) -> String {
        let trimmedPrompt = preferredPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedPrompt, !trimmedPrompt.isEmpty {
            return trimmedPrompt
        }
        return enhancer.promptForImageType(inputURL: inputURL)
    }

    func reconstructionIntent(
        for inputURL: URL,
        preset: EnhancementPreset,
        sceneOverride: ImageEnhancer.SceneType?
    ) -> ReconstructionIntent {
        let effectiveScene: ImageEnhancer.SceneType?
        if let sceneOverride {
            effectiveScene = sceneOverride
        } else if preset == .ecommerce {
            effectiveScene = .ecommerce
        } else if preset == .auto {
            effectiveScene = enhancer.detectSceneType(inputURL: inputURL)
        } else {
            effectiveScene = nil
        }

        return OpenAIImageReconstructionService.recommendedIntent(
            preset: preset,
            scene: effectiveScene
        )
    }
}

extension AIRunResolution {
    /// Resolución local (sin IA) a partir del snapshot del lote.
    static func local(from snapshot: BatchRunSnapshot) -> AIRunResolution {
        AIRunResolution(
            preset: snapshot.preset,
            format: snapshot.format,
            quality: snapshot.quality,
            upscaleTargetLongSide: nil,
            faceRestoreStrength: nil,
            aiSuggestedPreset: nil,
            aiSuggestedQuality: nil,
            aiReason: nil,
            aiPrompt: nil,
            aiTuning: nil,
            recipe: nil,
            usedFallback: false
        )
    }
}
