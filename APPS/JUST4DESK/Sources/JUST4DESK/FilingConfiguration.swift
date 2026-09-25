import Foundation

/// Configuración del archivado, persistida en UserDefaults.
enum FilingConfiguration {
    private static let rootPathKey = "just4desk.filing.rootPath"
    private static let sourcePathKey = "just4desk.filing.sourcePath"
    private static let sourcePathsKey = "just4desk.filing.sourcePaths"
    private static let simulationKey = "just4desk.filing.simulationMode"
    private static let pausedKey = "just4desk.filing.paused"

    /// Carpeta raíz de la organización de documentos (nil = sin configurar).
    static var rootPath: String? {
        get { UserDefaults.standard.string(forKey: rootPathKey) }
        set {
            if let newValue, !newValue.isEmpty {
                UserDefaults.standard.set(newValue, forKey: rootPathKey)
            } else {
                UserDefaults.standard.removeObject(forKey: rootPathKey)
            }
        }
    }

    /// Carpetas de entrada vigiladas (N4): pueden ser varias y se procesan todas.
    /// Compatibilidad: si solo existe la clave antigua (una carpeta), se migra al leer.
    static var sourcePaths: [String] {
        get {
            if let stored = UserDefaults.standard.stringArray(forKey: sourcePathsKey), !stored.isEmpty {
                return stored
            }
            if let legacy = UserDefaults.standard.string(forKey: sourcePathKey), !legacy.isEmpty {
                return [legacy]
            }
            return []
        }
        set {
            let cleaned = newValue.filter { !$0.isEmpty }
            UserDefaults.standard.set(cleaned, forKey: sourcePathsKey)
            // Mantener la clave antigua sincronizada con la primera (compat hacia atrás).
            if let first = cleaned.first {
                UserDefaults.standard.set(first, forKey: sourcePathKey)
            } else {
                UserDefaults.standard.removeObject(forKey: sourcePathKey)
            }
        }
    }

    /// Primera carpeta de entrada (compatibilidad con onboarding y textos).
    static var sourcePath: String? {
        get { sourcePaths.first }
        set {
            var paths = sourcePaths
            if let newValue, !newValue.isEmpty {
                if paths.isEmpty { paths = [newValue] } else { paths[0] = newValue }
            } else if !paths.isEmpty {
                paths.removeFirst()
            }
            sourcePaths = paths
        }
    }

    /// Añade una carpeta de entrada (estandarizada y sin duplicados).
    nonisolated static func adding(_ path: String, to paths: [String]) -> [String] {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        var seen = Set<String>()
        return (paths + [standardized]).filter { seen.insert($0).inserted }
    }

    /// Quita una carpeta de entrada (estandarizada).
    nonisolated static func removing(_ path: String, from paths: [String]) -> [String] {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        return paths.filter { $0 != standardized }
    }

    /// Modo simulación: registra propuestas sin mover nada.
    static var simulationMode: Bool {
        get { UserDefaults.standard.bool(forKey: simulationKey) }
        set { UserDefaults.standard.set(newValue, forKey: simulationKey) }
    }

    /// Organización pausada (persistente entre arranques).
    static var organizationPaused: Bool {
        get { UserDefaults.standard.bool(forKey: pausedKey) }
        set { UserDefaults.standard.set(newValue, forKey: pausedKey) }
    }

    static var rootURL: URL? {
        rootPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// Sugerencia por defecto de carpeta raíz (~/JUST4DESK).
    static var suggestedRootPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("JUST4DESK", isDirectory: true)
            .path
    }

    /// Sugerencia por defecto de carpeta de entrada (~/Descargas).
    static var suggestedSourcePath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Descargas", isDirectory: true)
            .path
    }

    /// Sugerencia de segunda entrada típica (~/Downloads del sistema).
    static var suggestedDownloadsPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads", isDirectory: true)
            .path
    }
}
