import Foundation
import J4IDocs

/// Resumen de contenido de una carpeta tratada como unidad de archivado.
public struct FolderContentSummary: Sendable, Equatable {
    public let fileCount: Int
    public let directoryCount: Int
    public let totalBytes: Int64
    public let extensionCounts: [String: Int]
    public let dominantExtension: String?
    public let sampleNames: [String]
    public let textSample: String

    /// Cáscara vacía: sin ficheros en todo el árbol (aunque contenga subcarpetas vacías).
    /// No hay nada que archivar → el pipeline la deja en origen (`skipped-empty`), no en sin clasificar.
    public var isEmpty: Bool { fileCount == 0 }
}

/// Perfila el contenido de una carpeta (extensión dominante, muestras de nombres y de texto)
/// para clasificarla como **unidad**: la IA y las reglas reciben un resumen compacto,
/// no el árbol crudo.
///
/// Límites (rendimiento y privacidad):
/// - Máx. 3.000 ficheros contabilizados.
/// - Texto solo de hasta 2 documentos de texto (pdf/docx/txt/…) ≤ 8 MB, truncado a 1.200 chars.
/// - `includeText: false` (listados rápidos, p. ej. «Por revisar»): no se lee texto de documentos.
public enum FolderProfiler {
    public static let maxFiles = 3000
    public static let maxTextFiles = 2
    public static let maxTextFileBytes: Int64 = 8 * 1024 * 1024
    public static let maxTextSampleCharacters = 1200

    static let textExtensions: Set<String> = ["pdf", "docx", "doc", "txt", "md", "rtf", "csv"]
    static let videoExtensions: Set<String> = ["mp4", "mkv", "mov", "avi", "webm", "m4v", "mpg", "mpeg", "wmv", "ts", "flv"]
    static let audioExtensions: Set<String> = ["m4a", "mp3", "aac", "wav", "flac", "ogg", "opus", "wma", "aiff", "alac"]
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "tiff", "bmp"]

    /// Prioridad de desempate por familia de medio (menor = gana en empate de cuenta).
    static func mediaPriority(_ ext: String) -> Int {
        if videoExtensions.contains(ext) { return 0 }
        if audioExtensions.contains(ext) { return 1 }
        if imageExtensions.contains(ext) { return 2 }
        return 3
    }

    public static func summarize(folderURL: URL, includeText: Bool = true) -> FolderContentSummary {
        let fileManager = FileManager.default
        var extensionCounts: [String: Int] = [:]
        var directoryCount = 0
        var fileCount = 0
        var totalBytes: Int64 = 0
        var sampleNames: [String] = []
        var textCandidates: [URL] = []

        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .fileSizeKey]
        if let enumerator = fileManager.enumerator(
            at: folderURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) {
            for case let url as URL in enumerator {
                if fileCount >= maxFiles { break }
                let values = try? url.resourceValues(forKeys: keys)
                if values?.isDirectory == true {
                    directoryCount += 1
                    continue
                }
                guard values?.isRegularFile == true else { continue }
                fileCount += 1
                let size = Int64(values?.fileSize ?? 0)
                totalBytes += size
                let ext = (url.lastPathComponent as NSString).pathExtension.lowercased()
                if !ext.isEmpty {
                    extensionCounts[ext, default: 0] += 1
                }
                if sampleNames.count < 12 {
                    sampleNames.append(url.lastPathComponent)
                }
                if includeText,
                   textCandidates.count < maxTextFiles,
                   textExtensions.contains(ext),
                   size > 0,
                   size <= maxTextFileBytes {
                    textCandidates.append(url)
                }
            }
        }

        // Extensión dominante: la más frecuente; a igualdad, prioridad por familia (vídeo → audio →
        // imagen → resto) y, por último, alfabético — así una carpeta de vídeo con 1 .mkv, 1 .m4a
        // y 1 .jpg no acaba clasificada como «Fotos».
        let dominant = extensionCounts
            .sorted { a, b in
                if a.value != b.value { return a.value > b.value }
                let priorityA = mediaPriority(a.key)
                let priorityB = mediaPriority(b.key)
                if priorityA != priorityB { return priorityA < priorityB }
                return a.key < b.key
            }
            .first?.key

        var textPieces: [String] = []
        if includeText {
            for url in textCandidates {
                if let text = DocumentAnalyzer.extractedText(from: url), !text.isEmpty {
                    textPieces.append("— \(url.lastPathComponent):\n\(String(text.prefix(maxTextSampleCharacters)))")
                }
            }
        }

        return FolderContentSummary(
            fileCount: fileCount,
            directoryCount: directoryCount,
            totalBytes: totalBytes,
            extensionCounts: extensionCounts,
            dominantExtension: dominant,
            sampleNames: sampleNames,
            textSample: textPieces.joined(separator: "\n\n")
        )
    }

    /// Texto-resumen legible que reciben las reglas y la IA (qué contiene la carpeta).
    public static func summaryText(folderName: String, summary: FolderContentSummary) -> String {
        var lines: [String] = []
        lines.append("Carpeta «\(folderName)» tratada como unidad de archivado.")
        lines.append("Contenido: \(summary.fileCount) fichero(s) en \(summary.directoryCount) subcarpeta(s); \(formattedBytes(summary.totalBytes)).")
        let topTypes = summary.extensionCounts
            .sorted { a, b in a.value == b.value ? a.key < b.key : a.value > b.value }
            .prefix(6)
            .map { ".\($0.key) × \($0.value)" }
        if !topTypes.isEmpty {
            lines.append("Tipos: \(topTypes.joined(separator: ", ")).")
        }
        if !summary.sampleNames.isEmpty {
            lines.append("Ejemplos: \(summary.sampleNames.prefix(12).joined(separator: "; ")).")
        }
        if !summary.textSample.isEmpty {
            lines.append("Muestra de texto:\n\(summary.textSample)")
        }
        return lines.joined(separator: "\n")
    }

    static func formattedBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
