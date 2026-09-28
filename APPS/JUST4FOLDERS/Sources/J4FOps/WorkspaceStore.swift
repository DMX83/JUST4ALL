import Foundation
import os

/// Ola 3 — «Workspaces» estilo QSpace: guarda el estado de los dos paneles (pestañas y
/// pestaña activa) + visibilidad del preview, con nombre, para restaurarlo después.
public struct PanelWorkspace: Codable, Sendable, Equatable {
    public var tabs: [String]
    public var activeIndex: Int

    public init(tabs: [String], activeIndex: Int) {
        self.tabs = tabs
        self.activeIndex = activeIndex
    }
}

public struct Workspace: Codable, Sendable, Equatable {
    public var name: String
    public var left: PanelWorkspace
    public var right: PanelWorkspace
    public var previewPaneVisible: Bool

    public init(name: String, left: PanelWorkspace, right: PanelWorkspace, previewPaneVisible: Bool) {
        self.name = name
        self.left = left
        self.right = right
        self.previewPaneVisible = previewPaneVisible
    }
}

/// Persistencia JSON de workspaces (Application Support/JUST4FOLDERS/workspaces.json).
public final class WorkspaceStore {
    public static let shared = WorkspaceStore()

    private let url: URL
    private var workspaces: [String: Workspace] = [:]

    public static func defaultURL(appFolder: String = "JUST4FOLDERS") -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base
            .appendingPathComponent(appFolder, isDirectory: true)
            .appendingPathComponent("workspaces.json", isDirectory: false)
    }

    public init(url: URL? = nil) {
        self.url = url ?? Self.defaultURL()
        load()
    }

    /// Todos los workspaces ordenados por nombre.
    public func all() -> [Workspace] {
        workspaces.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func workspace(named name: String) -> Workspace? {
        workspaces[name]
    }

    /// Crea o reemplaza un workspace por nombre.
    public func save(_ workspace: Workspace) {
        workspaces[workspace.name] = workspace
        persist()
    }

    @discardableResult
    public func remove(named name: String) -> Bool {
        guard workspaces.removeValue(forKey: name) != nil else { return false }
        persist()
        return true
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: Workspace].self, from: data) else { return }
        workspaces = decoded
    }

    private let logger = Logger(subsystem: "com.dmx83.just4folders", category: "workspaces")

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(workspaces)
            try data.write(to: url, options: .atomic)
        } catch {
            // Los workspaces son una comodidad: un fallo de escritura no rompe la app.
            logger.error("No se pudo guardar workspaces.json: \(error.localizedDescription, privacy: .public)")
        }
    }
}
