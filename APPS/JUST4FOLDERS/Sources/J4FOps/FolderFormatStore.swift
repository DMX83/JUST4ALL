import Foundation
import os

/// v2.0 — «Folder formats»: recuerda la vista por carpeta (aplanada, orden, ocultos),
/// como los formatos de carpeta de Directory Opus. Persistencia JSON en Application Support,
/// con LRU (500 carpetas) para acotar el tamaño.
public struct FolderFormat: Codable, Sendable, Equatable {
    public var flatView: Bool
    public var sortColumn: String
    public var ascending: Bool
    public var includeHidden: Bool
    /// Ola 2 — columnas ocultas (ids: name/size/modified/type); nil = todas visibles.
    public var hiddenColumns: [String]?
    /// Ola 3 — modo de vista por carpeta: "gallery" o nil (lista).
    public var viewMode: String?

    public init(
        flatView: Bool = false,
        sortColumn: String = "name",
        ascending: Bool = true,
        includeHidden: Bool = false,
        hiddenColumns: [String]? = nil,
        viewMode: String? = nil
    ) {
        self.flatView = flatView
        self.sortColumn = sortColumn
        self.ascending = ascending
        self.includeHidden = includeHidden
        self.hiddenColumns = hiddenColumns
        self.viewMode = viewMode
    }
}

public final class FolderFormatStore {
    public static let shared = FolderFormatStore()

    private let url: URL
    private let capacity: Int
    private var formats: [String: FolderFormat] = [:]
    private var order: [String] = []

    public static func defaultURL(appFolder: String = "JUST4FOLDERS") -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base
            .appendingPathComponent(appFolder, isDirectory: true)
            .appendingPathComponent("folder-formats.json", isDirectory: false)
    }

    public init(url: URL? = nil, capacity: Int = 500) {
        self.url = url ?? Self.defaultURL()
        self.capacity = capacity
        load()
    }

    /// Formato guardado para una carpeta (match exacto por ruta estandarizada).
    public func format(for path: String) -> FolderFormat? {
        formats[normalize(path)]
    }

    /// Guarda el formato de una carpeta (LRU: la más antigua se descarta al superar el tope).
    public func set(_ format: FolderFormat, for path: String) {
        let key = normalize(path)
        formats[key] = format
        order.removeAll { $0 == key }
        order.append(key)
        while order.count > capacity, let first = order.first {
            order.removeFirst()
            formats.removeValue(forKey: first)
        }
        save()
    }

    /// Olvida el formato de una carpeta.
    public func remove(for path: String) {
        let key = normalize(path)
        guard formats.removeValue(forKey: key) != nil else { return }
        order.removeAll { $0 == key }
        save()
    }

    private func normalize(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        guard let decoded = try? JSONDecoder().decode([String: FolderFormat].self, from: data) else { return }
        formats = decoded
        // Orden aproximado por recencia del archivo (para el LRU entre sesiones).
        order = decoded.keys.sorted()
    }

    private let logger = Logger(subsystem: "com.dmx83.just4folders", category: "folder-formats")

    private func save() {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(formats)
            try data.write(to: url, options: .atomic)
        } catch {
            // El formato es una comodidad: un fallo de escritura no debe afectar a la navegación.
            logger.error("No se pudo guardar folder-formats.json: \(error.localizedDescription, privacy: .public)")
        }
    }
}
