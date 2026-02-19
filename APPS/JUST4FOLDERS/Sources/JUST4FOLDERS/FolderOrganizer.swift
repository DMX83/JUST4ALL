import Foundation
import UniformTypeIdentifiers

enum FolderCategory: String, CaseIterable, Identifiable {
    case images = "Imagenes"
    case videos = "Videos"
    case audios = "Audios"
    case documents = "Documentos"
    case archives = "Comprimidos"
    case other = "Otros"

    var id: String { rawValue }

    var directoryName: String {
        switch self {
        case .images:
            return "Images"
        case .videos:
            return "Videos"
        case .audios:
            return "Audio"
        case .documents:
            return "Documents"
        case .archives:
            return "Archives"
        case .other:
            return "Other"
        }
    }

    static func from(url: URL) -> FolderCategory {
        let ext = url.pathExtension.lowercased()
        if ext.isEmpty {
            return .other
        }

        if let type = UTType(filenameExtension: ext) {
            if type.conforms(to: .image) { return .images }
            if type.conforms(to: .movie) || type.conforms(to: .video) { return .videos }
            if type.conforms(to: .audio) { return .audios }
            if type.conforms(to: .archive) { return .archives }
            if type.conforms(to: .pdf) || type.conforms(to: .text) || type.conforms(to: .spreadsheet) || type.conforms(to: .presentation) {
                return .documents
            }
        }

        switch ext {
        case "zip", "rar", "7z", "tar", "gz", "bz2", "xz":
            return .archives
        case "doc", "docx", "xls", "xlsx", "ppt", "pptx", "md", "rtf":
            return .documents
        default:
            return .other
        }
    }
}

struct FolderScanSummary {
    let sourceFolder: URL
    let totalFiles: Int
    let totalBytes: Int64
    let byCategory: [FolderCategory: Int]
}

enum FolderOrganizer {
    static func scan(folder: URL) throws -> FolderScanSummary {
        let files = try collectFiles(in: folder)
        var byCategory: [FolderCategory: Int] = [:]
        var totalBytes: Int64 = 0

        for file in files {
            let category = FolderCategory.from(url: file)
            byCategory[category, default: 0] += 1

            let fileSize = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            totalBytes += Int64(fileSize)
        }

        return FolderScanSummary(
            sourceFolder: folder,
            totalFiles: files.count,
            totalBytes: totalBytes,
            byCategory: byCategory
        )
    }

    static func organize(
        from sourceFolder: URL,
        to destinationFolder: URL,
        progressHandler: @escaping (_ current: Int, _ total: Int) -> Void
    ) throws {
        let files = try collectFiles(in: sourceFolder)
        let fileManager = FileManager.default

        if !fileManager.fileExists(atPath: destinationFolder.path) {
            try fileManager.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        }

        for (index, file) in files.enumerated() {
            let category = FolderCategory.from(url: file)
            let categoryFolder = destinationFolder.appendingPathComponent(category.directoryName, isDirectory: true)
            if !fileManager.fileExists(atPath: categoryFolder.path) {
                try fileManager.createDirectory(at: categoryFolder, withIntermediateDirectories: true)
            }

            let targetURL = uniqueTargetURL(for: file, in: categoryFolder)
            try fileManager.copyItem(at: file, to: targetURL)
            progressHandler(index + 1, files.count)
        }
    }

    private static func collectFiles(in folder: URL) throws -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isHiddenKey]
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants]
        ) else {
            return []
        }

        var files: [URL] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: Set(keys))
            if values.isHidden == true { continue }
            if values.isRegularFile == true {
                files.append(url)
            }
        }
        return files
    }

    private static func uniqueTargetURL(for sourceURL: URL, in folder: URL) -> URL {
        let fileManager = FileManager.default
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let ext = sourceURL.pathExtension
        var candidate = folder.appendingPathComponent(sourceURL.lastPathComponent)
        var counter = 1

        while fileManager.fileExists(atPath: candidate.path) {
            let suffix = "-\(counter)"
            let newName = ext.isEmpty ? "\(baseName)\(suffix)" : "\(baseName)\(suffix).\(ext)"
            candidate = folder.appendingPathComponent(newName)
            counter += 1
        }

        return candidate
    }
}
