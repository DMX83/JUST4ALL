import CoreServices
import Foundation
import J4ICore

/// Vigila una carpeta de entrada y notifica **unidades** (ficheros sueltos o carpetas)
/// cuando están "estables" (tamaño y fecha sin cambios durante N ticks de estabilidad).
///
/// - Unidad = elemento de primer nivel de la carpeta vigilada. Las carpetas se tratan como
///   unidades completas (se clasifican y mueven enteras, con su contenido): así no se rompen
///   apps portables ni árboles con estructura propia.
/// - Ignora ficheros ocultos, temporales de descarga (`.part`, `.crdownload`, …) y `~`.
/// - En `start` puede escanear TODO el contenido ya existente (backlog) de primer nivel.
/// - Si la carpeta no se puede ni listar (p. ej. TCC de macOS sin permiso), `start` falla con
///   un mensaje accionable en vez de quedarse en silencio.
/// - Los paths de FSEvents se normalizan contra la dualidad `/private` (lección de F1).
public final class SourceFolderWatcher {
    public typealias StableFileHandler = @Sendable (URL) -> Void

    private final class ContextBox {
        unowned let watcher: SourceFolderWatcher
        init(watcher: SourceFolderWatcher) {
            self.watcher = watcher
        }
    }

    private struct TrackedFile {
        var fileSize: Int64
        var modifiedAt: Date
        var stableTicks: Int
    }

    public static let ignoredExtensions: Set<String> = ["part", "download", "crdownload", "tmp", "cpgz", "partial"]

    public static func isIgnored(fileName: String) -> Bool {
        if fileName.hasPrefix(".") { return true }
        if fileName.hasSuffix("~") { return true }
        let ext = (fileName as NSString).pathExtension.lowercased()
        return ignoredExtensions.contains(ext)
    }

    private let queue = DispatchQueue(label: "j4i.source.watch", qos: .utility)
    private let stabilityInterval: TimeInterval
    private let minimumStableTicks: Int

    private var stream: FSEventStreamRef?
    private var contextPointer: UnsafeMutableRawPointer?
    private var watchedPath: String?
    private var resolvedPath: String?
    private var handler: StableFileHandler?
    private var tracked: [String: TrackedFile] = [:]
    private var ticker: DispatchSourceTimer?

    public init(stabilityInterval: TimeInterval = 2.0, minimumStableTicks: Int = 2) {
        self.stabilityInterval = max(0.5, stabilityInterval)
        self.minimumStableTicks = max(1, minimumStableTicks)
    }

    deinit {
        stop()
    }

    public func start(folder: URL, scanExisting: Bool = true, handler: @escaping StableFileHandler) throws {
        stop()
        let standardized = URL(fileURLWithPath: folder.path).standardizedFileURL.path
        watchedPath = standardized
        resolvedPath = URL(fileURLWithPath: standardized).resolvingSymlinksInPath().path
        self.handler = handler

        // Sonda de acceso (fail-fast): si no podemos listar la carpeta, ni FSEvents ni el backlog
        // servirán de nada — típico de macOS (TCC) sin permiso concedido. Mejor fallar aquí con un
        // mensaje accionable que quedarse en silencio sin escanear nada.
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: standardized)
        } catch {
            throw NSError(
                domain: "J4IDocs",
                code: 4302,
                userInfo: [NSLocalizedDescriptionKey: "Sin acceso a «\((standardized as NSString).abbreviatingWithTildeInPath)»: concede el permiso en Ajustes del Sistema → Privacidad y seguridad → Archivos y carpetas (o Acceso total al disco) y pulsa Reintentar."]
            )
        }

        let box = ContextBox(watcher: self)
        let pointer = Unmanaged.passRetained(box).toOpaque()
        contextPointer = pointer

        var context = FSEventStreamContext(version: 0, info: pointer, retain: nil, release: nil, copyDescription: nil)
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagNoDefer |
            kFSEventStreamCreateFlagUseCFTypes
        )
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, clientInfo, numEvents, eventPaths, _, _ in
                guard let clientInfo else { return }
                let box = Unmanaged<ContextBox>.fromOpaque(clientInfo).takeUnretainedValue()
                box.watcher.handleEvents(count: numEvents, paths: eventPaths)
            },
            &context,
            [standardized] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.4,
            flags
        ) else {
            Unmanaged<ContextBox>.fromOpaque(pointer).release()
            contextPointer = nil
            watchedPath = nil
            resolvedPath = nil
            self.handler = nil
            throw NSError(domain: "J4IDocs", code: 4301, userInfo: [NSLocalizedDescriptionKey: "No se pudo crear el stream de vigilancia."])
        }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)

        J4Log.info(.ingest, "Vigilando carpeta de entrada: «\((standardized as NSString).abbreviatingWithTildeInPath)» (estabilidad: \(minimumStableTicks) ticks × \(stabilityInterval) s).")
        if scanExisting {
            scanExistingFiles()
        }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + stabilityInterval, repeating: stabilityInterval)
        timer.setEventHandler { [weak self] in
            self?.evaluatePending()
        }
        timer.resume()
        ticker = timer
    }

    public func stop() {
        if watchedPath != nil {
            J4Log.debug(.ingest, "Vigilancia de la carpeta de entrada detenida.")
        }
        ticker?.cancel()
        ticker = nil
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
        if let pointer = contextPointer {
            Unmanaged<ContextBox>.fromOpaque(pointer).release()
        }
        contextPointer = nil
        handler = nil
        watchedPath = nil
        resolvedPath = nil
        tracked.removeAll()
    }

    // MARK: - Internals (siempre en `queue`)

    private func scanExistingFiles() {
        guard let watchedPath else { return }
        let folderURL = URL(fileURLWithPath: watchedPath, isDirectory: true)
        let contents: [URL]
        do {
            contents = try FileManager.default.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            J4Log.error(.ingest, "No se pudo leer la carpeta de entrada «\((watchedPath as NSString).abbreviatingWithTildeInPath)»: \(error.localizedDescription)")
            return
        }
        var registered = 0
        for url in contents {
            let name = url.lastPathComponent
            guard !Self.isIgnored(fileName: name) else { continue }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
            guard values?.isRegularFile == true || values?.isDirectory == true else { continue }
            registerPending(url: url)
            registered += 1
        }
        J4Log.info(.ingest, "Escaneo inicial de la carpeta de entrada: \(registered) unidad(es) pendientes de estabilizar (\(contents.count) elemento(s) en total).")
    }

    private func handleEvents(count: Int, paths: UnsafeMutableRawPointer) {
        guard count > 0 else { return }
        let pathArray = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as NSArray
        for index in 0..<count {
            guard let raw = pathArray[index] as? String,
                  let mapped = mapEventPath(raw) else { continue }
            let name = (mapped as NSString).lastPathComponent
            guard !Self.isIgnored(fileName: name) else {
                J4Log.debug(.ingest, "Ignorado (temporal u oculto): «\(name)».")
                continue
            }
            // Las unidades son los hijos directos de la carpeta vigilada: una carpeta nueva se
            // procesa entera (lo que ocurre dentro no genera trabajo por separado).
            let parent = (mapped as NSString).deletingLastPathComponent
            guard parent == watchedPath || parent == resolvedPath else { continue }
            guard FileManager.default.fileExists(atPath: mapped) else { continue }
            registerPending(url: URL(fileURLWithPath: mapped))
        }
    }

    private func mapEventPath(_ raw: String) -> String? {
        guard let watchedPath, let resolvedPath else { return nil }
        let bases = [watchedPath, resolvedPath]
        for base in bases where !base.isEmpty {
            if raw == base { return watchedPath }
            if raw.hasPrefix(base + "/") {
                return watchedPath + String(raw.dropFirst(base.count))
            }
        }
        let alternate = raw.hasPrefix("/private/") ? String(raw.dropFirst("/private".count)) : "/private" + raw
        for base in bases where !base.isEmpty {
            if alternate == base { return watchedPath }
            if alternate.hasPrefix(base + "/") {
                return watchedPath + String(alternate.dropFirst(base.count))
            }
        }
        return nil
    }

    private func registerPending(url: URL) {
        let path = url.standardizedFileURL.path
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        let modified = attributes?[.modificationDate] as? Date ?? Date()
        if var existing = tracked[path] {
            if existing.fileSize != size || existing.modifiedAt != modified {
                existing.fileSize = size
                existing.modifiedAt = modified
                existing.stableTicks = 0
            }
            tracked[path] = existing
        } else {
            tracked[path] = TrackedFile(fileSize: size, modifiedAt: modified, stableTicks: 0)
            J4Log.debug(.ingest, "Nuevo en la carpeta de entrada: «\(url.lastPathComponent)» (esperando estabilidad).")
        }
    }

    private func evaluatePending() {
        guard let handler else { return }
        var stablePaths: [String] = []
        for (path, trackedFile) in tracked {
            guard FileManager.default.fileExists(atPath: path) else {
                tracked.removeValue(forKey: path)
                J4Log.debug(.ingest, "Descartado «\((path as NSString).lastPathComponent)»: ya no existe.")
                continue
            }
            let attributes = try? FileManager.default.attributesOfItem(atPath: path)
            let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
            let modified = attributes?[.modificationDate] as? Date ?? Date()

            if size == trackedFile.fileSize, modified == trackedFile.modifiedAt {
                let ticks = trackedFile.stableTicks + 1
                if ticks >= minimumStableTicks {
                    stablePaths.append(path)
                } else {
                    var updated = trackedFile
                    updated.stableTicks = ticks
                    tracked[path] = updated
                }
            } else {
                var updated = trackedFile
                updated.fileSize = size
                updated.modifiedAt = modified
                updated.stableTicks = 0
                tracked[path] = updated
            }
        }
        for path in stablePaths {
            tracked.removeValue(forKey: path)
            handler(URL(fileURLWithPath: path))
        }
    }
}
