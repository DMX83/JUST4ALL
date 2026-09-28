import Foundation
import AppKit

/// Dominio de preview: orquestación de la generación de previews (original / PRO / IA /
/// reconstrucción) fuera de la vista. El estado vive en `PreviewStateViewModel`; aquí solo la lógica.
@MainActor
struct PreviewCoordinator {
    let processor: BatchItemProcessor

    /// Lanza la regeneración de preview cancelando el intento anterior.
    func scheduleRefresh(
        state: PreviewStateViewModel,
        aiState: AIResolutionViewModel,
        preset: EnhancementPreset,
        mode: EnhancementMode,
        log: @escaping (String) -> Void
    ) {
        state.previewTask?.cancel()
        let requestID = state.nextPreviewRequestID()
        state.previewTask = Task {
            await refresh(
                state: state,
                aiState: aiState,
                requestID: requestID,
                preset: preset,
                mode: mode,
                log: log
            )
        }
    }

    func refresh(
        state: PreviewStateViewModel,
        aiState: AIResolutionViewModel,
        requestID: UUID,
        preset: EnhancementPreset,
        mode: EnhancementMode,
        log: @escaping (String) -> Void
    ) async {
        guard let selectedPreviewURL = state.selectedPreviewURL else {
            state.originalPreviewImage = nil
            state.proPreviewImage = nil
            state.aiPreviewImage = nil
            state.previewNeedsRefresh = false
            return
        }

        state.isGeneratingPreview = true

        do {
            guard let original = NSImage(contentsOf: selectedPreviewURL) else {
                throw ImageEnhancerError.cannotLoadImage(selectedPreviewURL)
            }
            state.originalPreviewImage = original

            let proPreview = try processor.enhancer.enhancedPreviewImage(inputURL: selectedPreviewURL, preset: preset)
            if Task.isCancelled || state.previewRequestID != requestID {
                state.isGeneratingPreview = false
                return
            }
            state.proPreviewImage = proPreview

            if mode == .reconstructAI {
                let reconstructedPreview = try await processor.reconstruction.reconstructPreviewImage(
                    inputURL: selectedPreviewURL,
                    intent: processor.reconstructionIntent(
                        for: selectedPreviewURL,
                        preset: preset,
                        sceneOverride: state.effectivePreviewScene
                    )
                )
                if Task.isCancelled || state.previewRequestID != requestID {
                    state.isGeneratingPreview = false
                    return
                }
                state.aiPreviewImage = reconstructedPreview
            } else if let aiTuningForRun = aiState.tuningForRun {
                _ = processor.resolvedAIPrompt(for: selectedPreviewURL, preferredPrompt: aiState.promptHD)
                let aiPreview = try processor.enhancer.enhancedPreviewImage(
                    inputURL: selectedPreviewURL,
                    preset: preset,
                    tuning: aiTuningForRun,
                    faceRestoreStrength: aiState.recipeForRun?.faceRestore.flatMap { $0.enabled ? ($0.strength ?? 0.5) : nil },
                    upscaleTargetLongSide: aiState.recipeForRun?.upscaleTargetLongSide,
                    sceneOverride: aiState.recipeForRun?.mappedScene
                )
                if Task.isCancelled || state.previewRequestID != requestID {
                    state.isGeneratingPreview = false
                    return
                }
                state.aiPreviewImage = aiPreview
            } else {
                state.aiPreviewImage = nil
            }
            state.previewNeedsRefresh = false
        } catch {
            state.originalPreviewImage = nil
            state.proPreviewImage = nil
            state.aiPreviewImage = nil
            log("❌ Preview \(selectedPreviewURL.lastPathComponent): \(error.localizedDescription)")
        }

        state.isGeneratingPreview = false
    }

    /// Prepara la selección actual (original + escena/preset efectivos) sin generar previews.
    func prepareForSelection(
        state: PreviewStateViewModel,
        files: [URL],
        preset: EnhancementPreset
    ) {
        state.previewTask?.cancel()
        state.previewNeedsRefresh = false
        state.proPreviewImage = nil
        state.aiPreviewImage = nil

        guard let previewURL = state.selectedPreviewURL ?? files.first else {
            state.originalPreviewImage = nil
            state.effectivePreviewScene = nil
            state.effectivePreviewPreset = .auto
            return
        }

        if state.selectedPreviewURL == nil {
            state.selectedPreviewURL = previewURL
        }
        state.originalPreviewImage = NSImage(contentsOf: previewURL)
        state.effectivePreviewScene = processor.enhancer.detectSceneType(inputURL: previewURL)
        state.effectivePreviewPreset = processor.enhancer.effectivePreset(for: preset, inputURL: previewURL)
        state.previewNeedsRefresh = true
    }

    /// Invalida las previews procesadas (cambio de preset/modo, resolución IA, etc.).
    func invalidate(state: PreviewStateViewModel, hasPendingInput: Bool) {
        state.clearProcessedPreview()
        state.previewNeedsRefresh = state.selectedPreviewURL != nil || hasPendingInput
    }
}
