import Foundation

struct AIResolutionCacheKey: Hashable {
    let fileURL: URL
    let basePreset: EnhancementPreset
    let baseFormat: OutputFormat
}

enum AIResolutionOutcome {
    case cached(AIRunResolution)
    case fresh(AIRunResolution)
    case fallback(AIRunResolution, error: Error)
}

/// Dominio de IA: resuelve la configuración de ejecución por imagen (cache + asesor + planner +
/// fallback local), sin efectos de UI. La aplicación a la interfaz vive en la vista.
@MainActor
struct AIResolutionEngine {
    let advisor: OpenAIImageAdvisor
    let enhancer: ImageEnhancer

    func resolve(
        for fileURL: URL,
        basePreset: EnhancementPreset,
        baseFormat: OutputFormat,
        baseQuality: Double,
        cache: AIResolutionViewModel
    ) async -> AIResolutionOutcome {
        let cacheKey = AIResolutionCacheKey(
            fileURL: fileURL.standardizedFileURL,
            basePreset: basePreset,
            baseFormat: baseFormat
        )

        if let cached = cache.resolutionCache[cacheKey] {
            return .cached(cached)
        }

        let size = enhancer.pixelSize(for: fileURL)
        let dimensions = (width: Int(size?.width ?? 0), height: Int(size?.height ?? 0))

        do {
            let recommendation = try await advisor.recommendHD(
                inputURL: fileURL,
                fileName: fileURL.lastPathComponent,
                width: dimensions.width,
                height: dimensions.height,
                currentPreset: basePreset,
                currentFormat: baseFormat
            )

            let resolution = EnhancementPlanner.resolve(
                recommendation: recommendation,
                basePreset: basePreset,
                baseFormat: baseFormat,
                baseQuality: baseQuality
            )
            cache.resolutionCache[cacheKey] = resolution
            return .fresh(resolution)
        } catch {
            let fallback = EnhancementPlanner.fallbackPlan(
                fileName: fileURL.lastPathComponent,
                width: dimensions.width,
                height: dimensions.height,
                basePreset: basePreset,
                baseFormat: baseFormat,
                baseQuality: baseQuality
            )
            return .fallback(fallback, error: error)
        }
    }
}
