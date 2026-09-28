import Foundation

/// Naming de salida versionado y con manejo de colisiones (dominio, sin UI).
enum OutputPathResolver {
    static func suffix(for mode: EnhancementMode) -> String {
        switch mode {
        case .local:
            return "-enhanced"
        case .ai:
            return "-enhanced_ia"
        case .reconstructAI:
            return "-reconstruct_ia"
        }
    }

    static func uniqueOutputURL(
        for inputURL: URL,
        in directory: URL,
        format: OutputFormat,
        mode: EnhancementMode,
        buildStamp: String = BuildInfo.buildStamp,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> URL {
        let baseName = inputURL.deletingPathExtension().lastPathComponent
        let suffix = suffix(for: mode)
        let buildSuffix = buildStamp.replacingOccurrences(of: " ", with: "_")
        var candidate = directory.appendingPathComponent("\(baseName)\(suffix)-\(buildSuffix).\(format.fileExtension)")
        var index = 1

        while fileExists(candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName)\(suffix)-\(buildSuffix)-\(index).\(format.fileExtension)")
            index += 1
        }

        return candidate
    }
}
