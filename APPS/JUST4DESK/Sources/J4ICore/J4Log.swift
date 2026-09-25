import Foundation
import os

// MARK: - Niveles y categorías

/// Nivel de severidad de una entrada del registro.
public enum J4LogLevel: String, CaseIterable, Sendable, Comparable, Codable {
    case debug
    case info
    case warning
    case error

    /// Etiqueta corta para mostrar en la UI y en el archivo de registro.
    public var label: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "AVISO"
        case .error: return "ERROR"
        }
    }

    var order: Int {
        switch self {
        case .debug: return 0
        case .info: return 1
        case .warning: return 2
        case .error: return 3
        }
    }

    public static func < (lhs: J4LogLevel, rhs: J4LogLevel) -> Bool {
        lhs.order < rhs.order
    }
}

/// Subsistema de la app que emite la entrada (para filtrar en la UI).
public enum J4LogCategory: String, CaseIterable, Sendable, Codable {
    case app
    case search
    case index
    case watch
    case ingest
    case extract
    case ai
    case filing

    public var displayName: String {
        switch self {
        case .app: return "App"
        case .search: return "Búsqueda"
        case .index: return "Índice"
        case .watch: return "Vigilancia"
        case .ingest: return "Ingesta"
        case .extract: return "Extracción"
        case .ai: return "IA"
        case .filing: return "Archivado"
        }
    }
}

/// Entrada inmutable del registro.
public struct J4LogEntry: Identifiable, Sendable, Equatable {
    public let id: UInt64
    public let date: Date
    public let level: J4LogLevel
    public let category: J4LogCategory
    public let message: String
    /// Origen en el código, p. ej. `FilingCoordinator.swift:83`.
    public let source: String

    public init(id: UInt64, date: Date, level: J4LogLevel, category: J4LogCategory, message: String, source: String) {
        self.id = id
        self.date = date
        self.level = level
        self.category = category
        self.message = message
        self.source = source
    }
}

// MARK: - Núcleo

/// Núcleo del registro: buffer en memoria + stream en vivo + archivo en disco + registro unificado de macOS.
///
/// Es thread-safe: todo el estado mutable se toca en una cola serie interna.
/// Se instancia una vez como `J4Log.core`; los tests pueden crear instancias aisladas
/// (`J4LogCore(capacity:fileURL:usesOSLog:)`).
public final class J4LogCore: @unchecked Sendable {
    public static let subsystem = "com.dmx83.just4desk"

    public let capacity: Int
    public let fileURL: URL?

    private let usesOSLog: Bool
    private let queue = DispatchQueue(label: "com.dmx83.just4desk.log")
    private let fileFormatter: DateFormatter
    private var buffer: [J4LogEntry] = []
    private var nextID: UInt64 = 0
    private var continuations: [UUID: AsyncStream<J4LogEntry>.Continuation] = [:]
    private var fileHandle: FileHandle?
    private var writesSinceSizeCheck = 0
    private var osLoggers: [J4LogCategory: Logger] = [:]

    public init(capacity: Int = 5000, fileURL: URL? = nil, usesOSLog: Bool = true) {
        self.capacity = max(1, capacity)
        self.fileURL = fileURL
        self.usesOSLog = usesOSLog
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        self.fileFormatter = formatter
        if let fileURL {
            openFile(at: fileURL)
        }
    }

    deinit {
        try? fileHandle?.close()
    }

    // MARK: API pública

    public func log(
        _ level: J4LogLevel,
        _ category: J4LogCategory,
        _ message: String,
        file: String = #fileID,
        line: Int = #line
    ) {
        let source = Self.shortSource(file: file, line: line)
        queue.sync {
            nextID += 1
            let entry = J4LogEntry(id: nextID, date: Date(), level: level, category: category, message: message, source: source)
            buffer.append(entry)
            if buffer.count > capacity {
                buffer.removeFirst(buffer.count - capacity)
            }
            for continuation in continuations.values {
                continuation.yield(entry)
            }
            appendToFile(entry)
            emitToOSLog(entry)
        }
    }

    /// Últimas entradas retenidas en memoria (orden cronológico).
    public func entries(limit: Int = 2000) -> [J4LogEntry] {
        queue.sync {
            buffer.count <= limit ? buffer : Array(buffer.suffix(limit))
        }
    }

    /// Stream en vivo: recibe las entradas nuevas a partir de la suscripción.
    public func stream() -> AsyncStream<J4LogEntry> {
        AsyncStream(bufferingPolicy: .bufferingNewest(2000)) { continuation in
            let token = UUID()
            queue.sync { continuations[token] = continuation }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.queue.async { self.continuations[token] = nil }
            }
        }
    }

    public func clearBuffer() {
        queue.sync { buffer.removeAll() }
    }

    // MARK: Privado

    private static func shortSource(file: String, line: Int) -> String {
        let name = file.split(separator: "/").last.map(String.init) ?? file
        return "\(name):\(line)"
    }

    private func appendToFile(_ entry: J4LogEntry) {
        guard let fileURL else { return }
        if fileHandle == nil {
            openFile(at: fileURL)
        }
        guard let handle = fileHandle else { return }
        let line = "\(fileFormatter.string(from: entry.date)) [\(entry.level.label)] [\(entry.category.rawValue)] \(entry.message)    (\(entry.source))\n"
        if let data = line.data(using: .utf8) {
            do {
                try handle.write(contentsOf: data)
            } catch {
                fileHandle = nil
            }
        }
        writesSinceSizeCheck += 1
        if writesSinceSizeCheck >= 200 {
            writesSinceSizeCheck = 0
            rotateIfNeeded(at: fileURL)
        }
    }

    private func openFile(at url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        _ = try? handle.seekToEnd()
        fileHandle = handle
    }

    /// Rota el archivo (a `.1`) cuando supera ~2 MB, para que no crezca sin límite.
    private func rotateIfNeeded(at url: URL) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              size.intValue > 2_000_000 else { return }
        try? fileHandle?.close()
        fileHandle = nil
        let rotated = URL(fileURLWithPath: url.path + ".1")
        try? FileManager.default.removeItem(at: rotated)
        try? FileManager.default.moveItem(at: url, to: rotated)
        openFile(at: url)
    }

    private func emitToOSLog(_ entry: J4LogEntry) {
        guard usesOSLog else { return }
        let logger = osLogger(for: entry.category)
        let message = entry.message
        switch entry.level {
        case .debug:
            logger.debug("\(message, privacy: .public)")
        case .info:
            logger.notice("\(message, privacy: .public)")
        case .warning:
            logger.warning("\(message, privacy: .public)")
        case .error:
            logger.error("\(message, privacy: .public)")
        }
    }

    private func osLogger(for category: J4LogCategory) -> Logger {
        if let existing = osLoggers[category] {
            return existing
        }
        let logger = Logger(subsystem: Self.subsystem, category: category.rawValue)
        osLoggers[category] = logger
        return logger
    }
}

// MARK: - Fachada estática

/// Fachada de uso en todo el código: `J4Log.info(.filing, "Archivado «factura» → 01_Fiscal/Facturas")`.
public enum J4Log {
    public static let core = J4LogCore(capacity: 5000, fileURL: resolvedDefaultFileURL(), usesOSLog: true)

    public static func debug(_ category: J4LogCategory, _ message: String, file: String = #fileID, line: Int = #line) {
        core.log(.debug, category, message, file: file, line: line)
    }

    public static func info(_ category: J4LogCategory, _ message: String, file: String = #fileID, line: Int = #line) {
        core.log(.info, category, message, file: file, line: line)
    }

    public static func warn(_ category: J4LogCategory, _ message: String, file: String = #fileID, line: Int = #line) {
        core.log(.warning, category, message, file: file, line: line)
    }

    public static func error(_ category: J4LogCategory, _ message: String, file: String = #fileID, line: Int = #line) {
        core.log(.error, category, message, file: file, line: line)
    }

    public static func entries(limit: Int = 2000) -> [J4LogEntry] { core.entries(limit: limit) }
    public static func stream() -> AsyncStream<J4LogEntry> { core.stream() }
    public static func clearBuffer() { core.clearBuffer() }

    /// Archivo de registro activo (nil si se desactiva con `J4I_LOG_FILE=0`).
    public static var fileURL: URL? { core.fileURL }

    /// `~/Library/Logs/JUST4DESK/just4desk.log`.
    ///
    /// Devuelve nil si `J4I_LOG_FILE=0` o si el proceso corre bajo XCTest (los tests no
    /// contaminan el registro de la app).
    public static func resolvedDefaultFileURL() -> URL? {
        let environment = ProcessInfo.processInfo.environment
        guard environment["J4I_LOG_FILE"] != "0" else { return nil }
        if environment["XCTestConfigurationFilePath"] != nil || environment["XCTestBundlePath"] != nil {
            return nil
        }
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library", isDirectory: true)
        return base
            .appendingPathComponent("Logs/JUST4DESK", isDirectory: true)
            .appendingPathComponent("just4desk.log", isDirectory: false)
    }
}
