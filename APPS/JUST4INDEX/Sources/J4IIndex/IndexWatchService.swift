import CoreServices
import Foundation
import J4ICore

/// Ingesta incremental del índice vía FSEvents.
///
/// - Persiste el `eventId` por root para reanudar tras reinicios (replay de historial).
/// - Si FSEvents señala pérdida de eventos (`MustScanSubDirs`, drops, wrap de IDs),
///   delega la reconciliación en `onNeedsRescan` (el llamador decide un `reindex`).
/// - El procesamiento es stat-based: si el path existe → upsert (con escaneo de subárbol
///   para directorios); si no existe → borrado de la entrada y sus descendientes.
public final class IndexWatchService: @unchecked Sendable {
    public typealias RescanHandler = @Sendable (Int64, String) -> Void

    private final class StreamContextBox {
        unowned let service: IndexWatchService
        let rootID: Int64
        let rootPath: String
        let resolvedRootPath: String
        var lastEventID: UInt64

        init(service: IndexWatchService, rootID: Int64, rootPath: String, resolvedRootPath: String, lastEventID: UInt64) {
            self.service = service
            self.rootID = rootID
            self.rootPath = rootPath
            self.resolvedRootPath = resolvedRootPath
            self.lastEventID = lastEventID
        }

        /// Mapea un path de FSEvents a la forma original del root, para mantener coherencia
        /// con el crawler.
        ///
        /// Los eventos pueden llegar con el prefijo `/private` añadido (p. ej. `/private/var/…`
        /// para un root `/var/…`) o sin él, y `resolvingSymlinksInPath()` NO es fiable aquí:
        /// se comporta distinto con rutas existentes e inexistentes y puede normalizar
        /// `/private/X` → `/X`. Por eso se comparan directamente ambas formas conocidas.
        func mapEventPath(_ raw: String) -> String? {
            let bases = [rootPath, resolvedRootPath]
            for base in bases where !base.isEmpty {
                if raw == base { return rootPath }
                if raw.hasPrefix(base + "/") {
                    return rootPath + String(raw.dropFirst(base.count))
                }
            }
            // Variante con/sin el prefijo `/private` (dualidad /var ↔ /private/var).
            let alternate = raw.hasPrefix("/private/") ? String(raw.dropFirst("/private".count)) : "/private" + raw
            for base in bases where !base.isEmpty {
                if alternate == base { return rootPath }
                if alternate.hasPrefix(base + "/") {
                    return rootPath + String(alternate.dropFirst(base.count))
                }
            }
            return nil
        }
    }

    private struct WatchState {
        var stream: FSEventStreamRef?
        var contextBox: StreamContextBox?
        var contextPointer: UnsafeMutableRawPointer?
        var pendingPaths: Set<String> = []
        var debounceWork: DispatchWorkItem?
    }

    private let index: SearchIndex
    private let debounceInterval: TimeInterval
    private let queue = DispatchQueue(label: "j4i.index.watch", qos: .utility)
    private var watches: [Int64: WatchState] = [:]
    private let rescanHandler: RescanHandler?

    public init(index: SearchIndex, debounceInterval: TimeInterval = 0.7, onNeedsRescan: RescanHandler? = nil) {
        self.index = index
        self.debounceInterval = max(0.2, debounceInterval)
        self.rescanHandler = onNeedsRescan
    }

    deinit {
        // Nota: si el servicio se libera desde su propia cola, stopAll() haría un sync
        // sobre esa misma cola; en la práctica el ciclo de vida lo controla la app.
        stopAll()
    }

    public func startWatching(rootID: Int64, rootPath: String) async throws {
        let sinceEventID = try await index.lastEventID(forRoot: rootID)
        try queue.sync {
            guard watches[rootID] == nil else { return }
            let standardized = URL(fileURLWithPath: rootPath).standardizedFileURL.path
            let resolved = URL(fileURLWithPath: standardized).resolvingSymlinksInPath().path

            let box = StreamContextBox(
                service: self,
                rootID: rootID,
                rootPath: standardized,
                resolvedRootPath: resolved,
                lastEventID: sinceEventID ?? 0
            )
            let contextPointer = Unmanaged.passRetained(box).toOpaque()
            var context = FSEventStreamContext(
                version: 0,
                info: contextPointer,
                retain: nil,
                release: nil,
                copyDescription: nil
            )

            let createFlags = FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagFileEvents |
                kFSEventStreamCreateFlagNoDefer |
                kFSEventStreamCreateFlagUseCFTypes |
                kFSEventStreamCreateFlagWatchRoot
            )
            let sinceWhen = sinceEventID.map { FSEventStreamEventId($0) }
                ?? FSEventStreamEventId(kFSEventStreamEventIdSinceNow)

            let stream = FSEventStreamCreate(
                kCFAllocatorDefault,
                { _, clientInfo, numEvents, eventPaths, eventFlags, eventIds in
                    guard let clientInfo else { return }
                    let box = Unmanaged<StreamContextBox>.fromOpaque(clientInfo).takeUnretainedValue()
                    box.service.handleEvents(
                        box: box,
                        count: numEvents,
                        paths: eventPaths,
                        flags: eventFlags,
                        ids: eventIds
                    )
                },
                &context,
                [resolved] as CFArray,
                sinceWhen,
                0.3,
                createFlags
            )
            guard let stream else {
                Unmanaged<StreamContextBox>.fromOpaque(contextPointer).release()
                throw NSError(
                    domain: "J4IIndex",
                    code: 4201,
                    userInfo: [NSLocalizedDescriptionKey: "No se pudo crear el stream de FSEvents."]
                )
            }

            var state = WatchState()
            state.stream = stream
            state.contextBox = box
            state.contextPointer = contextPointer
            watches[rootID] = state

            FSEventStreamSetDispatchQueue(stream, queue)
            FSEventStreamStart(stream)
            let sinceDescription = sinceEventID.map { String($0) } ?? "ahora"
            J4Log.info(.watch, "Vigilancia incremental activa: «\((standardized as NSString).abbreviatingWithTildeInPath)» (eventId: \(sinceDescription)).")
        }
    }

    public func isWatching(rootID: Int64) -> Bool {
        queue.sync { watches[rootID] != nil }
    }

    public func stopWatching(rootID: Int64) {
        queue.sync {
            guard let state = watches.removeValue(forKey: rootID) else { return }
            J4Log.debug(.watch, "Vigilancia detenida (root \(rootID)).")
            state.debounceWork?.cancel()
            if let stream = state.stream {
                FSEventStreamStop(stream)
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
            }
            if let pointer = state.contextPointer {
                Unmanaged<StreamContextBox>.fromOpaque(pointer).release()
            }
        }
    }

    public func stopAll() {
        let ids = queue.sync { Array(watches.keys) }
        for id in ids {
            stopWatching(rootID: id)
        }
    }

    // MARK: - FSEvents (siempre en `queue`)

    private func handleEvents(
        box: StreamContextBox,
        count: Int,
        paths: UnsafeMutableRawPointer,
        flags: UnsafePointer<FSEventStreamEventFlags>,
        ids: UnsafePointer<FSEventStreamEventId>
    ) {
        guard count > 0 else { return }

        let rescanMask = FSEventStreamEventFlags(
            kFSEventStreamEventFlagMustScanSubDirs |
            kFSEventStreamEventFlagUserDropped |
            kFSEventStreamEventFlagKernelDropped |
            kFSEventStreamEventFlagEventIdsWrapped
        )

        let pathArray = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as NSArray
        var needsRescan = false
        var maxEventID = box.lastEventID

        for index in 0..<count {
            let eventFlags = flags[index]
            if eventFlags & rescanMask != 0 {
                needsRescan = true
            }
            maxEventID = max(maxEventID, UInt64(ids[index]))
            if let raw = pathArray[index] as? String, let mapped = box.mapEventPath(raw) {
                watches[box.rootID]?.pendingPaths.insert(mapped)
            }
        }
        box.lastEventID = maxEventID

        if needsRescan, rescanHandler != nil {
            watches[box.rootID]?.pendingPaths.removeAll()
            let rootID = box.rootID
            let rootPath = box.rootPath
            J4Log.warn(.watch, "FSEvents perdió eventos (root \(rootID)); se relanzará un reindexado completo.")
            queue.async { [weak self] in
                self?.rescanHandler?(rootID, rootPath)
            }
            return
        }

        scheduleProcessing(rootID: box.rootID)
    }

    private func scheduleProcessing(rootID: Int64) {
        guard var state = watches[rootID] else { return }
        state.debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.processPending(rootID: rootID)
        }
        state.debounceWork = work
        watches[rootID] = state
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }

    private func processPending(rootID: Int64) {
        guard let state = watches[rootID], let box = state.contextBox else { return }
        let paths = Array(state.pendingPaths)
        watches[rootID]?.pendingPaths.removeAll()
        let eventID = box.lastEventID
        if !paths.isEmpty {
            J4Log.debug(.watch, "\(paths.count) cambio(s) detectado(s) en la carpeta indexada (root \(rootID)).")
        }

        Task { [index] in
            if !paths.isEmpty {
                await Self.ingest(paths: paths, rootID: rootID, index: index)
            }
            if eventID > 0 {
                try? await index.setLastEventID(eventID, forRoot: rootID)
            }
        }
    }

    private static func ingest(paths: [String], rootID: Int64, index: SearchIndex) async {
        let fileManager = FileManager.default
        var fileWrites: [IndexEntryWrite] = []
        var removed: [String] = []
        var dirsToScan: [String] = []
        var coveredDirs: [String] = []

        for path in paths.sorted() {
            let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
            var isDirectory: ObjCBool = false

            // Un path que ya no existe se trata SIEMPRE como borrado (aunque su carpeta
            // padre también venga en el lote y se vaya a re-escanear: el escaneo solo
            // hace upsert de lo que existe, no elimina hijos desaparecidos).
            if !fileManager.fileExists(atPath: standardized, isDirectory: &isDirectory) {
                removed.append(standardized)
                continue
            }
            // Los ocultos (`.DS_Store`, …) no se indexan (coherente con el crawler); si ya
            // estaban en el índice, este paso los limpia.
            if (standardized as NSString).lastPathComponent.hasPrefix(".") {
                removed.append(standardized)
                continue
            }
            if coveredDirs.contains(where: { standardized == $0 || standardized.hasPrefix($0 + "/") }) {
                continue
            }
            if isDirectory.boolValue {
                coveredDirs.append(standardized)
                dirsToScan.append(standardized)
            } else {
                let url = URL(fileURLWithPath: standardized)
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                fileWrites.append(
                    IndexEntryWrite(
                        url: url,
                        isDirectory: false,
                        sizeBytes: Int64(values?.fileSize ?? 0),
                        modifiedAt: values?.contentModificationDate
                    )
                )
            }
        }

        if !fileWrites.isEmpty {
            _ = try? await index.upsertEntries(rootID: rootID, fileWrites)
        }
        if !removed.isEmpty {
            _ = try? await index.removeEntries(rootID: rootID, paths: removed)
        }
        if !dirsToScan.isEmpty {
            let crawler = IndexCrawler(index: index)
            for dir in dirsToScan {
                try? await crawler.crawlSubtree(rootID: rootID, path: dir)
            }
        }
        if !fileWrites.isEmpty || !removed.isEmpty || !dirsToScan.isEmpty {
            J4Log.debug(.watch, "Índice actualizado (root \(rootID)): +\(fileWrites.count) fichero(s), −\(removed.count) borrado(s), \(dirsToScan.count) subárbol(es).")
        }
    }
}
