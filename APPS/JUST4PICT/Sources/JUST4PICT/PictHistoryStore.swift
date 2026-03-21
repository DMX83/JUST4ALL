import Foundation

struct PictHistoryEntry: Codable, Hashable, Identifiable {
    let id: UUID
    let date: Date
    let inputFileName: String
    let outputPath: String
    let preset: String
    let format: String
    let aiSuggestedPreset: String?
    let aiSuggestedQuality: Double?
    let aiReason: String?
    let aiTuningSummary: String?
    let aiPrompt: String?
    let aiPromptSummary: String?
}

struct PictHistoryStore {
    private let defaults: UserDefaults
    private let storageKey = "just4pict.history.entries"
    private let maxEntries = 80

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [PictHistoryEntry] {
        guard let data = defaults.data(forKey: storageKey) else {
            return []
        }
        return (try? JSONDecoder().decode([PictHistoryEntry].self, from: data)) ?? []
    }

    func save(_ entries: [PictHistoryEntry]) {
        guard let data = try? JSONEncoder().encode(Array(entries.prefix(maxEntries))) else {
            return
        }
        defaults.set(data, forKey: storageKey)
    }

    func prepend(
        current: [PictHistoryEntry],
        inputFileName: String,
        outputURL: URL,
        preset: EnhancementPreset,
        format: OutputFormat,
        aiSuggestedPreset: String? = nil,
        aiSuggestedQuality: Double? = nil,
        aiReason: String? = nil,
        aiTuningSummary: String? = nil,
        aiPrompt: String? = nil,
        storeFullPrompt: Bool = false
    ) -> [PictHistoryEntry] {
        var updated = current
        let sanitizedPrompt = aiPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = makePromptSummary(sanitizedPrompt)
        let entry = PictHistoryEntry(
            id: UUID(),
            date: Date(),
            inputFileName: inputFileName,
            outputPath: outputURL.path,
            preset: preset.rawValue,
            format: format.rawValue,
            aiSuggestedPreset: aiSuggestedPreset,
            aiSuggestedQuality: aiSuggestedQuality,
            aiReason: aiReason,
            aiTuningSummary: aiTuningSummary,
            aiPrompt: storeFullPrompt ? sanitizedPrompt : nil,
            aiPromptSummary: summary
        )
        updated.insert(entry, at: 0)
        let trimmed = Array(updated.prefix(maxEntries))
        save(trimmed)
        return trimmed
    }

    private func makePromptSummary(_ prompt: String?) -> String? {
        guard let prompt, !prompt.isEmpty else { return nil }
        let compact = prompt.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !compact.isEmpty else { return nil }
        if compact.count <= 140 {
            return compact
        }
        let idx = compact.index(compact.startIndex, offsetBy: 140)
        return String(compact[..<idx]) + "…"
    }
}
