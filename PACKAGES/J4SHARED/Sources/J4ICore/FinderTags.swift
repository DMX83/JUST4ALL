import Darwin
import Foundation

/// G5.1 — Etiquetas nativas del Finder (metadatos que viajan con el fichero).
///
/// Lee/escribe el atributo extendido `com.apple.metadata:_kMDItemUserTags` (plist binario con un
/// array de strings; una etiqueta con color se representa como «Nombre\nÍndice-de-color»).
/// **Añadir es aditivo** (se fusiona con las etiquetas existentes de cualquier otra app), quitar
/// es reversible y, si no queda ninguna, el atributo se elimina. Nunca se toca el contenido.
public enum FinderTags {
    public static let attributeName = "com.apple.metadata:_kMDItemUserTags"

    /// Resultado de una operación sobre un fichero.
    public enum Change: Sendable, Equatable {
        case updated
        case unchanged
        case failed
    }

    public struct BatchResult: Sendable, Equatable {
        public let updated: Int
        public let unchanged: Int
        public let failed: Int

        public var processed: Int { updated + unchanged + failed }
    }

    /// Etiquetas actuales del fichero, por nombre (sin color). Vacío si no tiene o no se puede leer.
    public static func names(of url: URL) -> [String] {
        rawTags(of: url).map(displayName)
    }

    /// Añade etiquetas (fusión con las existentes; ignora las que ya estén por nombre).
    @discardableResult
    public static func add(_ names: [String], to url: URL) -> Change {
        let target = names
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !target.isEmpty else { return .unchanged }
        var current = rawTags(of: url)
        let existing = Set(current.map(displayName))
        var changed = false
        for name in target where !existing.contains(name) {
            current.append(name)
            changed = true
        }
        guard changed else { return .unchanged }
        return writeAttribute(url, tags: current)
    }

    /// Quita las etiquetas indicadas (comparando por nombre, ignorando color).
    @discardableResult
    public static func remove(_ names: [String], from url: URL) -> Change {
        let target = Set(names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        guard !target.isEmpty else { return .unchanged }
        let current = rawTags(of: url)
        let filtered = current.filter { !target.contains(displayName($0)) }
        guard filtered.count != current.count else { return .unchanged }
        if filtered.isEmpty {
            return removeAttribute(url)
        }
        return writeAttribute(url, tags: filtered)
    }

    /// Lote: aplica (o quita) las etiquetas a varias rutas. Los ficheros inexistentes cuentan como fallo.
    public static func apply(_ names: [String], to urls: [URL], removing: Bool = false) -> BatchResult {
        var updated = 0
        var unchanged = 0
        var failed = 0
        for url in urls {
            guard FileManager.default.fileExists(atPath: url.path) else {
                failed += 1
                continue
            }
            let change = removing ? remove(names, from: url) : add(names, to: url)
            switch change {
            case .updated: updated += 1
            case .unchanged: unchanged += 1
            case .failed: failed += 1
            }
        }
        return BatchResult(updated: updated, unchanged: unchanged, failed: failed)
    }

    /// Escribe etiquetas «en crudo» (formato Finder, admite color `Nombre\nÍndice`). Interno (tests).
    @discardableResult
    static func setRawTags(_ tags: [String], of url: URL) -> Bool {
        writeAttribute(url, tags: tags) == .updated
    }

    // MARK: - Internals

    private static func displayName(_ tag: String) -> String {
        tag.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? tag
    }

    private static func rawTags(of url: URL) -> [String] {
        guard let data = readAttribute(url), !data.isEmpty else { return [] }
        let list = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return (list as? [String]) ?? []
    }

    private static func readAttribute(_ url: URL) -> Data? {
        let path = url.path
        let size = getxattr(path, attributeName, nil, 0, 0, 0)
        guard size > 0 else { return nil }
        var data = Data(count: size)
        let read = data.withUnsafeMutableBytes { buffer -> Int in
            guard let base = buffer.baseAddress else { return -1 }
            return getxattr(path, attributeName, base, size, 0, 0)
        }
        guard read > 0 else { return nil }
        if read < size { data = data.prefix(read) }
        return data
    }

    private static func writeAttribute(_ url: URL, tags: [String]) -> Change {
        guard let data = try? PropertyListSerialization.data(fromPropertyList: tags, format: .binary, options: 0) else {
            return .failed
        }
        let result = data.withUnsafeBytes { buffer -> Int32 in
            setxattr(url.path, attributeName, buffer.baseAddress, data.count, 0, 0)
        }
        return result == 0 ? .updated : .failed
    }

    private static func removeAttribute(_ url: URL) -> Change {
        if removexattr(url.path, attributeName, 0) == 0 {
            return .updated
        }
        return errno == ENOATTR ? .unchanged : .failed
    }
}
