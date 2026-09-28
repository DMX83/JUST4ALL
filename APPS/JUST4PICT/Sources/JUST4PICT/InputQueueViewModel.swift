import Foundation
import SwiftUI

/// Cola de entrada de imágenes (selección por lotes, carpetas y deduplicación), sin UI.
@MainActor
final class InputQueueViewModel: ObservableObject {
    @Published private(set) var files: [URL] = []
    @Published var outputDirectory: URL?

    let supportedExtensions: Set<String>

    init(supportedExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "webp", "tif", "tiff", "bmp", "gif"]) {
        self.supportedExtensions = supportedExtensions
    }

    /// Añade ficheros soportados y deduplicados (por URL estandarizada).
    /// Devuelve cuántos ficheros normalizados se presentaron, aunque ya estuvieran en cola.
    @discardableResult
    func merge(_ newFiles: [URL]) -> Int {
        let normalized = newFiles
            .filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
            .map { $0.standardizedFileURL }

        var current = Set(files.map(\.standardizedFileURL))
        for file in normalized where !current.contains(file) {
            files.append(file)
            current.insert(file)
        }
        return normalized.count
    }

    /// Recorre una carpeta (sin ocultos) y devuelve los ficheros de imagen soportados.
    func collectImages(in folder: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var result: [URL] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            if supportedExtensions.contains(url.pathExtension.lowercased()) {
                result.append(url)
            }
        }
        return result
    }

    func clear() {
        files.removeAll()
    }
}
