import Foundation

/// Dominio de resultados de batch: registra éxitos/fallos en el estado del lote, el historial
/// y la actividad, fuera de la vista.
@MainActor
struct BatchOutcomeRecorder {
    let historyStore: PictHistoryStore
    let enhancer: ImageEnhancer

    /// Registra un éxito y devuelve el historial actualizado.
    func recordSuccess(
        inputURL: URL,
        outputURL: URL,
        mode: EnhancementMode,
        sourcePreset: EnhancementPreset,
        resolution: AIRunResolution,
        totalCount: Int,
        retry: Bool = false,
        history: [PictHistoryEntry],
        storeFullPrompt: Bool,
        batchState: BatchStateViewModel,
        log: (String) -> Void
    ) -> [PictHistoryEntry] {
        batchState.batchResults[inputURL] = BatchItemResult(status: .success, outputURL: outputURL, errorMessage: nil, mode: mode)

        let updatedHistory = historyStore.prepend(
            current: history,
            inputFileName: inputURL.lastPathComponent,
            outputURL: outputURL,
            preset: sourcePreset,
            effectiveAutoDecision: autoDecision(for: inputURL, sourcePreset: sourcePreset, resolution: resolution),
            format: resolution.format,
            aiSuggestedPreset: resolution.aiSuggestedPreset,
            aiSuggestedQuality: resolution.aiSuggestedQuality,
            aiReason: resolution.aiReason,
            aiTuningSummary: Self.aiTuningSummary(resolution.aiTuning),
            aiPrompt: resolution.aiPrompt,
            storeFullPrompt: storeFullPrompt
        )

        let fallbackSuffix = resolution.usedFallback ? " (fallback local)" : ""
        let retryPrefix = retry ? "Reintento " : ""
        log("\(Self.modeLogPrefix(mode)) ✅ \(retryPrefix)\(inputURL.lastPathComponent) → \(outputURL.lastPathComponent)\(fallbackSuffix)")
        batchState.recomputeCounters(total: totalCount)
        return updatedHistory
    }

    /// Registra un fallo en el estado del lote y la actividad.
    func recordFailure(
        inputURL: URL,
        mode: EnhancementMode,
        error: Error,
        totalCount: Int,
        retry: Bool = false,
        batchState: BatchStateViewModel,
        log: (String) -> Void
    ) {
        batchState.batchResults[inputURL] = BatchItemResult(status: .failed, outputURL: nil, errorMessage: error.localizedDescription, mode: mode)
        let retryPrefix = retry ? "Reintento " : ""
        log("\(Self.modeLogPrefix(mode)) ❌ \(retryPrefix)\(inputURL.lastPathComponent): \(error.localizedDescription)")
        batchState.recomputeCounters(total: totalCount)
    }

    /// Etiqueta de decisión AUTO para el historial (solo se registra con preset AUTO).
    func autoDecision(
        for inputURL: URL,
        sourcePreset: EnhancementPreset,
        resolution: AIRunResolution
    ) -> String? {
        guard sourcePreset == .auto else { return nil }

        if let scene = resolution.recipe?.mappedScene {
            return scene.displayLabel
        }

        return enhancer.detectSceneType(inputURL: inputURL)?.displayLabel ?? "General"
    }

    static func modeLogPrefix(_ mode: EnhancementMode) -> String {
        switch mode {
        case .local:
            return "[PRO]"
        case .ai:
            return "[IA]"
        case .reconstructAI:
            return "[IA-R]"
        }
    }

    static func aiTuningSummary(_ tuning: AIEnhancementTuning?) -> String? {
        guard let tuning else { return nil }
        return "sombras \(Int(tuning.shadowAmount * 100)), luces \(Int(tuning.highlightAmount * 100)), vibrance \(Int(tuning.vibrance * 100)), nitidez \(Int(tuning.sharpen * 100))"
    }
}

extension ImageEnhancer.SceneType {
    /// Etiqueta visible de la escena detectada/efectiva.
    var displayLabel: String {
        switch self {
        case .portrait:
            return "Retrato"
        case .document:
            return "Documento"
        case .landscape:
            return "Paisaje"
        case .ecommerce:
            return "Ecommerce"
        case .darkPhoto:
            return "Foto oscura"
        case .generic:
            return "General"
        }
    }
}
