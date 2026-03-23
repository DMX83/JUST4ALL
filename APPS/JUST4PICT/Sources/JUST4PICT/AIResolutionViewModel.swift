import Foundation
import SwiftUI

struct AIResolutionCacheKey: Hashable {
    let fileURL: URL
    let basePreset: EnhancementPreset
    let baseFormat: OutputFormat
}

@MainActor
final class AIResolutionViewModel: ObservableObject {
    @Published var statusMessage = "IA lista"
    @Published var promptHD = ""
    @Published var suggestedPresetForRun: String?
    @Published var suggestedQualityForRun: Double?
    @Published var reasonForRun: String?
    @Published var tuningForRun: AIEnhancementTuning?
    @Published var recipeForRun: EnhancementRecipe?
    @Published var usedFallbackForRun = false

    var resolutionCache: [AIResolutionCacheKey: AIRunResolution] = [:]

    func reset(status: String = "IA lista") {
        statusMessage = status
        suggestedPresetForRun = nil
        suggestedQualityForRun = nil
        reasonForRun = nil
        tuningForRun = nil
        recipeForRun = nil
        usedFallbackForRun = false
    }

    func clearCache() {
        resolutionCache.removeAll()
    }
}
