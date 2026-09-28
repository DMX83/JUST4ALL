import Foundation
import os
import J4IIndex

/// v1.1 — Búsqueda del commander sobre el índice FTS5 compartido (`J4IIndex`, PACKAGES/J4SHARED).
///
/// Sustituye a `PathSearchIndex` (recorrido propio del árbol): aquí cada root se crawlea una vez
/// (cooperativo y cancelable) y las búsquedas son consultas FTS5 (<100 ms tras indexar), con
/// poda de lo que ya no existe en disco. El índice vive en
/// `~/Library/Application Support/JUST4FOLDERS/search-index.sqlite`, separado del de JUST4DESK.
actor IndexedSearchService {
    static let shared = IndexedSearchService()

    /// Resultado con la misma forma que el antiguo `PathIndexHit` (los llamantes no cambian de mapa).
    struct Hit: Sendable, Hashable {
        let path: String
        let name: String
        let isDirectory: Bool
        let sizeBytes: Int64
        let modifiedTimeInterval: TimeInterval
    }

    private let log = Logger(subsystem: "com.dmx83.just4folders", category: "index")
    private let index: SearchIndex
    private let crawler: IndexCrawler

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let base = appSupport.appendingPathComponent("JUST4FOLDERS", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let dbURL = base.appendingPathComponent("search-index.sqlite", isDirectory: false)
        let index = SearchIndex(databaseURL: dbURL)
        self.index = index
        self.crawler = IndexCrawler(index: index)
    }

    // MARK: - Estado

    /// ¿La carpeta ya está crawleada y lista para consultas?
    func isIndexed(for root: URL) async -> Bool {
        guard let current = await rootAndState(for: root.standardizedFileURL.path) else { return false }
        return current.state == .ready
    }

    // MARK: - Indexado

    /// Asegura (cooperativo) que cada root pedido esté crawleado. Idempotente: los ya listos se saltan.
    func ensureIndexedCooperative(
        roots: [URL],
        includeHidden: Bool,
        batchSize: Int = 400,
        pausePerBatchMS: UInt64 = 20
    ) async throws {
        let unique = Array(Set(roots.map { $0.standardizedFileURL.path })).sorted()
        for path in unique {
            try Task.checkCancellation()
            let rootURL = URL(fileURLWithPath: path, isDirectory: true)
            guard Self.isDirectory(rootURL) else { continue }
            try await ensureCrawled(
                root: rootURL,
                includeHidden: includeHidden,
                batchSize: batchSize,
                pausePerBatchMS: pausePerBatchMS
            )
        }
    }

    // MARK: - Búsqueda

    /// Búsqueda instantánea: si la carpeta aún no está indexada, se crawlea antes (cooperativo);
    /// después la consulta es FTS5 sobre el subárbol, sin recorrer el árbol a mano.
    func searchPreparing(query: String, under root: URL, includeHidden: Bool, limit: Int = 5000) async throws -> [Hit] {
        try await ensureCrawled(
            root: root.standardizedFileURL,
            includeHidden: includeHidden,
            batchSize: 800,
            pausePerBatchMS: 8
        )
        return try await search(query: query, under: root, limit: limit)
    }

    /// Consulta FTS5 limitada al subárbol de `root`.
    func search(query: String, under root: URL, limit: Int = 5000) async throws -> [Hit] {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return [] }
        var filters = IndexSearchFilters()
        filters.pathPrefix = root.standardizedFileURL.path
        let request = IndexSearchRequest(query: clean, filters: filters, limit: limit, includeContent: false)
        let hits = try await index.search(request)

        // Auto-curación: lo borrado fuera de la app no se devuelve y se poda del índice.
        var alive: [Hit] = []
        var missing: [String] = []
        for hit in hits {
            if FileManager.default.fileExists(atPath: hit.entry.path) {
                alive.append(
                    Hit(
                        path: hit.entry.path,
                        name: hit.entry.name,
                        isDirectory: hit.entry.isDirectory,
                        sizeBytes: hit.entry.sizeBytes,
                        modifiedTimeInterval: hit.entry.modifiedAt?.timeIntervalSince1970 ?? 0
                    )
                )
            } else {
                missing.append(hit.entry.path)
            }
        }
        if !missing.isEmpty, let rootInfo = try? await index.rootID(containing: root.standardizedFileURL.path) {
            let removed = (try? await index.removeEntries(rootID: rootInfo.id, paths: missing)) ?? 0
            if removed > 0 {
                log.info("Índice: \(removed, privacy: .public) entrada(s) podadas (ya no existen en disco).")
            }
        }
        return alive
    }

    // MARK: - Cambios externos (watcher de la app)

    /// Refresca el índice tras cambios detectados por el watcher: upsert de lo nuevo/modificado,
    /// crawl del subárbol para carpetas nuevas y borrado de lo desaparecido.
    func refreshChangedPaths(_ changedPaths: [String], watchedRoot: URL, includeHidden: Bool) async {
        let stdRoot = watchedRoot.standardizedFileURL.path
        guard let current = await rootAndState(for: stdRoot) else { return }
        guard current.state != .crawling else { return }
        let root = current.root
        let options = CrawlOptions(includeHidden: includeHidden, batchSize: 800, pausePerBatchMilliseconds: 8)
        for raw in Set(changedPaths) {
            let std = URL(fileURLWithPath: raw).standardizedFileURL.path
            guard std == stdRoot || std.hasPrefix(stdRoot + "/") else { continue }
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: std, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    try? await crawler.crawlSubtree(rootID: root.id, path: std, options: options)
                } else if let write = Self.entryWrite(for: std) {
                    _ = try? await index.upsertEntries(rootID: root.id, [write])
                }
            } else {
                _ = try? await index.removeEntries(rootID: root.id, paths: [std])
            }
        }
    }

    // MARK: - Privados

    private func ensureCrawled(root: URL, includeHidden: Bool, batchSize: Int, pausePerBatchMS: UInt64) async throws {
        guard Self.isDirectory(root) else { return }
        let path = root.path
        let current = await rootAndState(for: path)
        if current?.state == .ready {
            return
        }
        let rootRow: IndexRoot
        if let existing = current?.root {
            rootRow = existing
        } else {
            rootRow = try await index.addRoot(path: path)
        }
        let options = CrawlOptions(
            includeHidden: includeHidden,
            batchSize: max(100, batchSize),
            pausePerBatchMilliseconds: pausePerBatchMS
        )
        _ = try await crawler.crawl(rootID: rootRow.id, rootPath: path, options: options)
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    /// Root registrado (si existe) con su estado actual.
    private func rootAndState(for path: String) async -> (root: IndexRoot, state: IndexRootState)? {
        guard let root = ((try? await index.allRoots()) ?? []).first(where: { $0.path == path }) else {
            return nil
        }
        let state = (try? await index.rootStatus(id: root.id))?.state ?? .pending
        return (root, state)
    }

    private static func entryWrite(for path: String) -> IndexEntryWrite? {
        let url = URL(fileURLWithPath: path)
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey]) else {
            return nil
        }
        return IndexEntryWrite(
            path: path,
            isDirectory: values.isDirectory == true,
            sizeBytes: Int64(values.fileSize ?? 0),
            modifiedAt: values.contentModificationDate
        )
    }
}
