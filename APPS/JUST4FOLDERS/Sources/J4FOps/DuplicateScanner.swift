import CryptoKit
import Foundation

/// v1.2 — Detección de duplicados por tamaño + SHA-256 en streaming.
///
/// Primera criba barata por tamaño (solo se hashean ficheros con compañeros del mismo
/// tamaño); después SHA-256 cooperativo (cancelable). Nunca borra nada: solo agrupa.
public enum DuplicateScanner {

    public struct Group: Sendable, Equatable {
        /// Ficheros idénticos, ordenados por ruta.
        public let files: [URL]
        public let sizeBytes: Int64

        /// Bytes recuperables conservando una copia.
        public var wastedBytes: Int64 {
            sizeBytes * Int64(max(0, files.count - 1))
        }
    }

    /// Grupos de duplicados bajo `root`, ordenados por desperdicio descendente.
    public static func find(in root: URL, includeHidden: Bool = false, minSize: Int64 = 1) async throws -> [Group] {
        let candidates = enumerateCandidates(in: root, includeHidden: includeHidden, minSize: minSize)
        try Task.checkCancellation()

        var bySize: [Int64: [URL]] = [:]
        for (url, size) in candidates {
            bySize[size, default: []].append(url)
        }

        var groups: [Group] = []
        for (size, urls) in bySize where urls.count > 1 {
            var byDigest: [String: [URL]] = [:]
            for url in urls {
                try Task.checkCancellation()
                guard let digest = try? streamSHA256(of: url) else { continue }
                byDigest[digest, default: []].append(url)
            }
            for files in byDigest.values where files.count > 1 {
                groups.append(Group(files: files.sorted { $0.path < $1.path }, sizeBytes: size))
            }
        }
        return groups.sorted { $0.wastedBytes > $1.wastedBytes }
    }

    /// Ficheros regulares con tamaño ≥ `minSize` (cooperativo).
    nonisolated private static func enumerateCandidates(
        in root: URL,
        includeHidden: Bool,
        minSize: Int64
    ) -> [(URL, Int64)] {
        var options: FileManager.DirectoryEnumerationOptions = []
        if !includeHidden {
            options.insert(.skipsHiddenFiles)
        }
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: options
        ) else { return [] }

        var result: [(URL, Int64)] = []
        for case let item as URL in enumerator {
            if Task.isCancelled { break }
            guard let values = try? item.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            let size = Int64(values.fileSize ?? 0)
            guard size >= minSize else { continue }
            result.append((item, size))
        }
        return result
    }

    /// SHA-256 en streaming (bloques de 1 MiB) — no carga el fichero entero en memoria.
    nonisolated static func streamSHA256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1 << 20) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
            if Task.isCancelled { throw CancellationError() }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
