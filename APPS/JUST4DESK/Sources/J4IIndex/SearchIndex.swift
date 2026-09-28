import Foundation
import J4ICore
import SQLite3

/// Índice local de JUST4DESK (SQLite + FTS5).
///
/// Principios de diseño (lecciones de JUST4FOLDERS):
/// - La búsqueda NUNCA enumera el árbol: siempre consulta este índice.
/// - El filtrado por subárbol usa rangos de `path` (indexables), nunca `LIKE '%...%'`.
/// - La completitud se trackea por root (`state`), no por "hay alguna fila".
///   El estado lo gobiernan el crawler y el servicio de FSEvents.
///
/// Esquema v1: `roots`, `entries`, `entries_fts` (rowid = entries.id),
/// `doc_text`, `doc_text_fts` (rowid = entries.id).
public actor SearchIndex {
    public static let shared = SearchIndex()

    public static let schemaVersion: Int32 = 4

    private let dbURL: URL
    private var db: OpaquePointer?
    private var didOpen = false

    public init(databaseURL: URL? = nil) {
        if let databaseURL {
            self.dbURL = databaseURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            let base = appSupport.appendingPathComponent("JUST4DESK", isDirectory: true)
            self.dbURL = base.appendingPathComponent("index.sqlite", isDirectory: false)
        }
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    // MARK: - Roots

    @discardableResult
    public func addRoot(path: String) throws -> IndexRoot {
        try openIfNeeded()
        let std = URL(fileURLWithPath: path).standardizedFileURL.path
        let now = Date().timeIntervalSince1970
        try exec(
            "INSERT OR IGNORE INTO roots(path, added_ts, state) VALUES(?, ?, ?);",
            [.text(std), .double(now), .text(IndexRootState.pending.rawValue)]
        )
        guard let root = try fetchRoot(path: std) else {
            throw IndexError.sqlFailed("No se pudo registrar el root \(std).")
        }
        return root
    }

    public func allRoots() throws -> [IndexRoot] {
        try openIfNeeded()
        let sql = "SELECT id, path, added_ts FROM roots ORDER BY path;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw sqliteError("No se pudo preparar consulta de roots.")
        }
        defer { sqlite3_finalize(stmt) }
        var roots: [IndexRoot] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            roots.append(makeRoot(from: stmt))
        }
        return roots
    }

    public func removeRoot(id: Int64) throws {
        try openIfNeeded()
        try inTransaction {
            try deleteEntriesSQL(rootID: id)
            try exec("DELETE FROM roots WHERE id = ?;", [.int(id)])
        }
    }

    public func rootStatus(id: Int64) throws -> RootStatus {
        try openIfNeeded()
        let sql = "SELECT id, path, added_ts, state, last_event_id, scanned_count FROM roots WHERE id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw sqliteError("No se pudo preparar consulta de root.")
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, id)
        guard sqlite3_step(stmt) == SQLITE_ROW else {
            throw IndexError.sqlFailed("Root \(id) no encontrado.")
        }
        let root = makeRoot(from: stmt)
        let state = IndexRootState(rawValue: columnText(stmt, 3) ?? "") ?? .pending
        let lastEventID: UInt64? = sqlite3_column_type(stmt, 4) == SQLITE_NULL
            ? nil
            : UInt64(bitPattern: sqlite3_column_int64(stmt, 4))
        let scanned = sqlite3_column_int64(stmt, 5)
        let count = try entryCount(rootID: id)
        return RootStatus(root: root, state: state, lastEventID: lastEventID, scannedCount: scanned, entryCount: count)
    }

    public func setRootState(id: Int64, state: IndexRootState) throws {
        try openIfNeeded()
        try exec("UPDATE roots SET state = ? WHERE id = ?;", [.text(state.rawValue), .int(id)])
        if state == .ready {
            try exec("UPDATE roots SET last_crawl_ts = ? WHERE id = ?;", [.double(Date().timeIntervalSince1970), .int(id)])
        }
    }

    public func setRootCrawlProgress(id: Int64, scanned: Int64) throws {
        try openIfNeeded()
        try exec("UPDATE roots SET scanned_count = ? WHERE id = ?;", [.int(scanned), .int(id)])
    }

    public func lastEventID(forRoot id: Int64) throws -> UInt64? {
        try openIfNeeded()
        let value = try scalarInt64("SELECT last_event_id FROM roots WHERE id = ?;", [.int(id)])
        guard let value else { return nil }
        return UInt64(bitPattern: value)
    }

    public func setLastEventID(_ eventID: UInt64, forRoot id: Int64) throws {
        try openIfNeeded()
        try exec("UPDATE roots SET last_event_id = ? WHERE id = ?;", [.int(Int64(bitPattern: eventID)), .int(id)])
    }

    // MARK: - Escritura de entradas

    /// Upsert por lotes (una transacción). Reemplaza por `path` para no duplicar.
    @discardableResult
    public func upsertEntries(rootID: Int64, _ entries: [IndexEntryWrite]) throws -> Int {
        try openIfNeeded()
        guard !entries.isEmpty else { return 0 }

        var written = 0
        try inTransaction {
            for entry in entries {
                // Al reindexar una ruta la entrada se re-crea con un id nuevo: conserva el texto
                // extraído y el vector semántico de la entrada anterior para no perderlos.
                let carriedText = try documentTextForPath(entry.path)
                let carriedEmbedding = try embeddingForPath(entry.path)
                try deleteFTSRows(paths: [entry.path])
                try exec("DELETE FROM doc_text_fts WHERE rowid IN (SELECT id FROM entries WHERE path = ?);", [.text(entry.path)])
                try exec("DELETE FROM doc_text WHERE entry_id IN (SELECT id FROM entries WHERE path = ?);", [.text(entry.path)])
                try exec("DELETE FROM embeddings WHERE entry_id IN (SELECT id FROM entries WHERE path = ?);", [.text(entry.path)])
                try exec("DELETE FROM entries WHERE path = ?;", [.text(entry.path)])
                let parent = (entry.path as NSString).deletingLastPathComponent
                try exec(
                    """
                    INSERT INTO entries(root_id, path, parent_path, name, name_norm, ext, is_dir, size_bytes, modified_ts)
                    VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?);
                    """,
                    [
                        .int(rootID),
                        .text(entry.path),
                        .text(parent),
                        .text(entry.name),
                        .text(Self.foldForContains(entry.name)),
                        .text(entry.ext),
                        .int(entry.isDirectory ? 1 : 0),
                        .int(entry.sizeBytes),
                        entry.modifiedAt.map { SQLBind.double($0.timeIntervalSince1970) } ?? .null
                    ]
                )
                let rowID = sqlite3_last_insert_rowid(db)
                try exec(
                    "INSERT INTO entries_fts(rowid, path, name) VALUES(?, ?, ?);",
                    [.int(rowID), .text(entry.path), .text(entry.name)]
                )
                if let carriedText, !carriedText.isEmpty {
                    try exec(
                        "INSERT INTO doc_text(entry_id, text, updated_ts) VALUES(?, ?, ?);",
                        [.int(rowID), .text(carriedText), .double(Date().timeIntervalSince1970)]
                    )
                    try exec("INSERT INTO doc_text_fts(rowid, text) VALUES(?, ?);", [.int(rowID), .text(carriedText)])
                }
                if let carriedEmbedding {
                    try exec(
                        "INSERT INTO embeddings(entry_id, model, dim, source, vec, updated_ts) VALUES(?, ?, ?, ?, ?, ?);",
                        [
                            .int(rowID),
                            .text(carriedEmbedding.model),
                            .int(Int64(carriedEmbedding.dim)),
                            .text(carriedEmbedding.source),
                            .blob(carriedEmbedding.vec),
                            .double(Date().timeIntervalSince1970)
                        ]
                    )
                }
                written += 1
            }
        }
        embeddingCache = nil
        return written
    }

    /// Elimina entradas (subárbol inclusivo) bajo cada path, scoped al root.
    @discardableResult
    public func removeEntries(rootID: Int64, paths: [String]) throws -> Int {
        try openIfNeeded()
        guard !paths.isEmpty else { return 0 }
        var removed = 0
        try inTransaction {
            for path in paths {
                let std = URL(fileURLWithPath: path).standardizedFileURL.path
                let lo = std + "/"
                let hi = lo + "\u{10FFFF}"
                removed += try countEntries(rootID: rootID, path: std, lo: lo, hi: hi)
                try exec(
                    "DELETE FROM doc_text_fts WHERE rowid IN (SELECT id FROM entries WHERE root_id = ? AND (path = ? OR (path >= ? AND path < ?)));",
                    [.int(rootID), .text(std), .text(lo), .text(hi)]
                )
                try exec(
                    "DELETE FROM doc_text WHERE entry_id IN (SELECT id FROM entries WHERE root_id = ? AND (path = ? OR (path >= ? AND path < ?)));",
                    [.int(rootID), .text(std), .text(lo), .text(hi)]
                )
                try exec(
                    "DELETE FROM embeddings WHERE entry_id IN (SELECT id FROM entries WHERE root_id = ? AND (path = ? OR (path >= ? AND path < ?)));",
                    [.int(rootID), .text(std), .text(lo), .text(hi)]
                )
                try exec(
                    "DELETE FROM entries_fts WHERE rowid IN (SELECT id FROM entries WHERE root_id = ? AND (path = ? OR (path >= ? AND path < ?)));",
                    [.int(rootID), .text(std), .text(lo), .text(hi)]
                )
                try exec(
                    "DELETE FROM entries WHERE root_id = ? AND (path = ? OR (path >= ? AND path < ?));",
                    [.int(rootID), .text(std), .text(lo), .text(hi)]
                )
            }
        }
        return removed
    }

    public func clearEntries(rootID: Int64) throws {
        try openIfNeeded()
        try inTransaction {
            try deleteEntriesSQL(rootID: rootID)
        }
    }

    // MARK: - Consultas para sugerencias proactivas (G2)

    /// Tamaños de fichero distintos presentes en el índice (≥ `minBytes`).
    ///
    /// Detector barato de posibles duplicados: dos copias idénticas del mismo contenido
    /// **siempre** comparten tamaño; el hash se verifica solo para los candidatos.
    public func indexedFileSizes(minBytes: Int64 = 0) throws -> Set<Int64> {
        try openIfNeeded()
        let sql = "SELECT DISTINCT size_bytes FROM entries WHERE is_dir = 0 AND size_bytes >= ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw sqliteError("No se pudo preparar la consulta de tamaños.")
        }
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, [.int(minBytes)])
        var sizes = Set<Int64>()
        while sqlite3_step(stmt) == SQLITE_ROW {
            sizes.insert(sqlite3_column_int64(stmt, 0))
        }
        return sizes
    }

    /// Ficheros grandes del índice (≥ `minBytes`), opcionalmente sin cambios desde `olderThan`,
    /// de mayor a menor tamaño (límite `limit`). Alimenta el detector «grandes y olvidados» (G2).
    public func largeFiles(minBytes: Int64, olderThan: Date? = nil, limit: Int = 25) throws -> [IndexEntry] {
        try openIfNeeded()
        var sql = """
        SELECT id, root_id, path, name, ext, is_dir, size_bytes, modified_ts
        FROM entries
        WHERE is_dir = 0 AND size_bytes >= ?
        """
        var binds: [SQLBind] = [.int(minBytes)]
        if let olderThan {
            sql += " AND modified_ts IS NOT NULL AND modified_ts <= ?"
            binds.append(.double(olderThan.timeIntervalSince1970))
        }
        sql += " ORDER BY size_bytes DESC LIMIT ?;"
        binds.append(.int(Int64(max(1, limit))))
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw sqliteError("No se pudo preparar la consulta de ficheros grandes.")
        }
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, binds)
        var rows: [IndexEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(makeEntry(from: stmt))
        }
        return rows
    }

    // MARK: - Texto de documentos (búsqueda por contenido)

    public func setDocumentText(entryID: Int64, text: String) throws {
        try openIfNeeded()
        try inTransaction {
            try exec(
                """
                INSERT INTO doc_text(entry_id, text, updated_ts) VALUES(?, ?, ?)
                ON CONFLICT(entry_id) DO UPDATE SET text = excluded.text, updated_ts = excluded.updated_ts;
                """,
                [.int(entryID), .text(text), .double(Date().timeIntervalSince1970)]
            )
            try exec("DELETE FROM doc_text_fts WHERE rowid = ?;", [.int(entryID)])
            try exec("INSERT INTO doc_text_fts(rowid, text) VALUES(?, ?);", [.int(entryID), .text(text)])
        }
    }

    public func documentText(entryID: Int64) throws -> String? {
        try openIfNeeded()
        let sql = "SELECT text FROM doc_text WHERE entry_id = ? LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw sqliteError("No se pudo preparar consulta de texto.")
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, entryID)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return columnText(stmt, 0)
    }

    // MARK: - Semántica (G7): embeddings locales

    /// Entrada pendiente de (re)vectorizar: sin vector, vectorizada solo por nombre cuando ya hay
    /// texto del documento, o vectorizada con otro modelo.
    public struct EmbeddingCandidate: Sendable, Equatable {
        public let entryID: Int64
        public let name: String
        public let documentText: String?
    }

    private var embeddingCache: (model: String, contentOnly: Bool, count: Int64, rows: [(entryID: Int64, vector: [Float])])?

    /// Candidatos a vectorizar con `model` (tope por lote para el rellenado en segundo plano).
    public func embeddingCandidates(model: String, limit: Int = 64) throws -> [EmbeddingCandidate] {
        try openIfNeeded()
        let sql = """
        SELECT e.id, e.name, dt.text
        FROM entries e
        LEFT JOIN embeddings em ON em.entry_id = e.id AND em.model = ?
        LEFT JOIN doc_text dt ON dt.entry_id = e.id
        WHERE e.is_dir = 0
          AND (em.entry_id IS NULL OR (em.source = 'name' AND dt.text IS NOT NULL AND dt.text != ''))
        ORDER BY e.id
        LIMIT ?;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw sqliteError("No se pudo preparar candidatos de embeddings.")
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, model, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 2, Int64(limit))
        var rows: [EmbeddingCandidate] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(
                EmbeddingCandidate(
                    entryID: sqlite3_column_int64(stmt, 0),
                    name: columnText(stmt, 1) ?? "",
                    documentText: columnText(stmt, 2)
                )
            )
        }
        return rows
    }

    /// Guarda (o reemplaza) el vector normalizado de una entrada.
    public func setEmbedding(entryID: Int64, model: String, source: String, vector: [Float]) throws {
        try openIfNeeded()
        try exec(
            """
            INSERT INTO embeddings(entry_id, model, dim, source, vec, updated_ts) VALUES(?, ?, ?, ?, ?, ?)
            ON CONFLICT(entry_id) DO UPDATE SET
                model = excluded.model, dim = excluded.dim, source = excluded.source,
                vec = excluded.vec, updated_ts = excluded.updated_ts;
            """,
            [
                .int(entryID),
                .text(model),
                .int(Int64(vector.count)),
                .text(source),
                .blob(Self.packFloats(vector)),
                .double(Date().timeIntervalSince1970)
            ]
        )
        embeddingCache = nil
    }

    /// (vectorizados con `model`, ficheros totales) para el estado que muestra la UI.
    public func embeddingStats(model: String) throws -> (embedded: Int64, files: Int64) {
        try openIfNeeded()
        let embedded = try scalarInt64("SELECT COUNT(*) FROM embeddings WHERE model = ?;", [.text(model)]) ?? 0
        let files = try scalarInt64("SELECT COUNT(*) FROM entries WHERE is_dir = 0;", []) ?? 0
        return (embedded, files)
    }

    /// Mejores aciertos por similitud semántica (producto punto; `queryVector` normalizado).
    /// Con `contentOnly` solo puntúan los vectores construidos con el texto del documento
    /// (los de nombre se reservan a otras funciones: en corpus cortos añaden más ruido que señal).
    public func semanticHits(
        queryVector: [Float],
        model: String,
        limit: Int = 10,
        filters: IndexSearchFilters = .init(),
        contentOnly: Bool = false
    ) throws -> [IndexSearchHit] {
        try openIfNeeded()
        let snapshot = try embeddingSnapshot(model: model, contentOnly: contentOnly)
        guard !snapshot.isEmpty else { return [] }
        var scored: [(entryID: Int64, score: Double)] = []
        for row in snapshot where row.vector.count == queryVector.count {
            var dot: Float = 0
            for index in queryVector.indices { dot += row.vector[index] * queryVector[index] }
            scored.append((row.entryID, Double(dot)))
        }
        scored.sort { $0.score > $1.score }
        let top = Array(scored.prefix(max(limit * 3, limit)))
        let entriesByID = Dictionary(uniqueKeysWithValues: try entries(ids: top.map(\.entryID)).map { ($0.id, $0) })
        var hits: [IndexSearchHit] = []
        for row in top {
            guard hits.count < limit else { break }
            guard let entry = entriesByID[row.entryID], Self.matches(filters: filters, entry: entry) else { continue }
            hits.append(
                IndexSearchHit(
                    entry: entry,
                    score: row.score,
                    matchedContent: false,
                    contentSnippet: nil,
                    matchedSemantically: true
                )
            )
        }
        return hits
    }

    /// Entradas por id, en el orden pedido (omite ids inexistentes).
    public func entries(ids: [Int64]) throws -> [IndexEntry] {
        try openIfNeeded()
        guard !ids.isEmpty else { return [] }
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        let sql = """
        SELECT e.id, e.root_id, e.path, e.name, e.ext, e.is_dir, e.size_bytes, e.modified_ts
        FROM entries e WHERE e.id IN (\(placeholders));
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw sqliteError("No se pudo preparar la consulta por ids.")
        }
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, ids.map { .int($0) })
        var byID: [Int64: IndexEntry] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            let entry = makeEntry(from: stmt)
            byID[entry.id] = entry
        }
        return ids.compactMap { byID[$0] }
    }

    /// Snapshot cacheado de vectores (se invalida al escribir embeddings o cambiar el conteo).
    private func embeddingSnapshot(model: String, contentOnly: Bool = false) throws -> [(entryID: Int64, vector: [Float])] {
        let sourceClause = contentOnly ? " AND source = 'content'" : ""
        let count = try scalarInt64("SELECT COUNT(*) FROM embeddings WHERE model = ?\(sourceClause);", [.text(model)]) ?? 0
        if let cache = embeddingCache, cache.model == model, cache.contentOnly == contentOnly, cache.count == count {
            return cache.rows
        }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT entry_id, dim, vec FROM embeddings WHERE model = ?\(sourceClause);", -1, &stmt, nil) == SQLITE_OK else {
            throw sqliteError("No se pudo preparar la lectura de embeddings.")
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, model, -1, SQLITE_TRANSIENT)
        var rows: [(entryID: Int64, vector: [Float])] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let entryID = sqlite3_column_int64(stmt, 0)
            let dim = Int(sqlite3_column_int64(stmt, 1))
            guard let data = columnBlob(stmt, 2), let vector = Self.unpackFloats(data, count: dim) else { continue }
            rows.append((entryID, vector))
        }
        embeddingCache = (model, contentOnly, count, rows)
        return rows
    }

    private static func matches(filters: IndexSearchFilters, entry: IndexEntry) -> Bool {
        if let rootID = filters.rootID, entry.rootID != rootID { return false }
        if let extensions = filters.extensions {
            guard !entry.isDirectory, extensions.contains(entry.ext) else { return false }
        }
        if let directoriesOnly = filters.directoriesOnly, directoriesOnly, !entry.isDirectory { return false }
        if let minSize = filters.minSizeBytes, entry.sizeBytes < minSize { return false }
        if let maxSize = filters.maxSizeBytes, entry.sizeBytes > maxSize { return false }
        if let after = filters.modifiedAfter {
            guard let modified = entry.modifiedAt, modified >= after else { return false }
        }
        if let before = filters.modifiedBefore {
            guard let modified = entry.modifiedAt, modified <= before else { return false }
        }
        if let prefix = filters.pathPrefix, !entry.path.hasPrefix(prefix) { return false }
        return true
    }

    static func packFloats(_ floats: [Float]) -> Data {
        var data = Data(capacity: floats.count * 4)
        for value in floats {
            var bits = value.bitPattern.littleEndian
            withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
        }
        return data
    }

    static func unpackFloats(_ data: Data, count: Int) -> [Float]? {
        guard count > 0, data.count == count * 4 else { return nil }
        var floats = [Float](repeating: 0, count: count)
        data.withUnsafeBytes { raw in
            for index in 0..<count {
                let bits = raw.loadUnaligned(fromByteOffset: index * 4, as: UInt32.self)
                floats[index] = Float(bitPattern: UInt32(littleEndian: bits))
            }
        }
        return floats
    }

    // MARK: - Re-extracción de contenido (G7.3)

    /// Fichero pendiente de extraer texto (sin fila en `doc_text`: ni texto ni intento previo).
    public struct ContentCandidate: Sendable, Equatable {
        public let entryID: Int64
        public let path: String
        public let name: String
    }

    /// Candidatos a extracción de contenido: extensión soportada y `doc_text` ausente. Los intentos
    /// sin texto quedan marcados con una fila vacía, así que no se repiten en cada arranque.
    public func contentCandidates(extensions: [String], limit: Int = 48) throws -> [ContentCandidate] {
        try openIfNeeded()
        guard !extensions.isEmpty else { return [] }
        let placeholders = Array(repeating: "?", count: extensions.count).joined(separator: ",")
        let sql = """
        SELECT e.id, e.path, e.name
        FROM entries e
        LEFT JOIN doc_text dt ON dt.entry_id = e.id
        WHERE e.is_dir = 0 AND dt.entry_id IS NULL AND lower(e.ext) IN (\(placeholders))
        ORDER BY COALESCE(e.modified_ts, 0) DESC, e.id DESC
        LIMIT ?;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw sqliteError("No se pudo preparar candidatos de contenido.")
        }
        defer { sqlite3_finalize(stmt) }
        var binds = extensions.map { SQLBind.text($0) }
        binds.append(.int(Int64(limit)))
        try bind(stmt, binds)
        var rows: [ContentCandidate] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(
                ContentCandidate(
                    entryID: sqlite3_column_int64(stmt, 0),
                    path: columnText(stmt, 1) ?? "",
                    name: columnText(stmt, 2) ?? ""
                )
            )
        }
        return rows
    }

    /// Marca un intento de extracción sin texto útil: fila vacía en `doc_text` («ya se intentó»).
    public func markContentAttempted(entryID: Int64) throws {
        try openIfNeeded()
        try exec(
            """
            INSERT INTO doc_text(entry_id, text, updated_ts) VALUES(?, '', ?)
            ON CONFLICT(entry_id) DO NOTHING;
            """,
            [.int(entryID), .double(Date().timeIntervalSince1970)]
        )
    }

    /// Borra filas de texto de entradas que ya no existen (histórico de reindexados anteriores).
    @discardableResult
    public func sweepOrphanContent() throws -> Int {
        try openIfNeeded()
        let removed = try scalarInt64("SELECT COUNT(*) FROM doc_text WHERE entry_id NOT IN (SELECT id FROM entries);", []) ?? 0
        if removed > 0 {
            try exec("DELETE FROM doc_text_fts WHERE rowid NOT IN (SELECT id FROM entries);")
            try exec("DELETE FROM doc_text WHERE entry_id NOT IN (SELECT id FROM entries);")
        }
        return Int(removed)
    }

    // MARK: - Reindexado conservador (G7.4)

    /// Copia a tablas temporales el texto y los vectores de un root antes de un reindexado
    /// completo, para re-vincularlos por ruta después (las entradas se recrean con ids nuevos).
    public func preserveContentSnapshot(rootID: Int64) throws {
        try openIfNeeded()
        try exec("DROP TABLE IF EXISTS j4i_keep_text;")
        try exec("DROP TABLE IF EXISTS j4i_keep_embeddings;")
        try exec(
            """
            CREATE TEMP TABLE j4i_keep_text AS
            SELECT e.path AS path, dt.text AS text
            FROM doc_text dt JOIN entries e ON e.id = dt.entry_id
            WHERE e.root_id = ?;
            """,
            [.int(rootID)]
        )
        try exec(
            """
            CREATE TEMP TABLE j4i_keep_embeddings AS
            SELECT e.path AS path, em.model AS model, em.dim AS dim, em.source AS source,
                   em.vec AS vec, em.updated_ts AS updated_ts
            FROM embeddings em JOIN entries e ON e.id = em.entry_id
            WHERE e.root_id = ?;
            """,
            [.int(rootID)]
        )
        let texts = try scalarInt64("SELECT COUNT(*) FROM j4i_keep_text;", []) ?? 0
        let vectors = try scalarInt64("SELECT COUNT(*) FROM j4i_keep_embeddings;", []) ?? 0
        J4Log.info(.index, "Reindexado: preservados \(texts) texto(s) y \(vectors) vector(es) para re-vincular.")
    }

    /// Re-vincula por ruta el contenido preservado (llamar después del crawl del reindexado).
    @discardableResult
    public func restorePreservedContent(rootID: Int64) throws -> Int {
        try openIfNeeded()

        let textsToRestore = try scalarInt64(
            """
            SELECT COUNT(*) FROM j4i_keep_text k
            JOIN entries e ON e.path = k.path AND e.root_id = ?
            WHERE k.text != '';
            """,
            [.int(rootID)]
        ) ?? 0
        if textsToRestore > 0 {
            try exec(
                """
                INSERT OR REPLACE INTO doc_text(entry_id, text, updated_ts)
                SELECT e.id, k.text, ? FROM j4i_keep_text k
                JOIN entries e ON e.path = k.path AND e.root_id = ?
                WHERE k.text != '';
                """,
                [.double(Date().timeIntervalSince1970), .int(rootID)]
            )
            try exec(
                """
                DELETE FROM doc_text_fts WHERE rowid IN (
                    SELECT e.id FROM j4i_keep_text k
                    JOIN entries e ON e.path = k.path AND e.root_id = ?
                    WHERE k.text != ''
                );
                """,
                [.int(rootID)]
            )
            try exec(
                """
                INSERT INTO doc_text_fts(rowid, text)
                SELECT e.id, k.text FROM j4i_keep_text k
                JOIN entries e ON e.path = k.path AND e.root_id = ?
                WHERE k.text != '';
                """,
                [.int(rootID)]
            )
        }

        let vectorsToRestore = try scalarInt64(
            """
            SELECT COUNT(*) FROM j4i_keep_embeddings k
            JOIN entries e ON e.path = k.path AND e.root_id = ?;
            """,
            [.int(rootID)]
        ) ?? 0
        if vectorsToRestore > 0 {
            try exec(
                """
                INSERT OR REPLACE INTO embeddings(entry_id, model, dim, source, vec, updated_ts)
                SELECT e.id, k.model, k.dim, k.source, k.vec, k.updated_ts FROM j4i_keep_embeddings k
                JOIN entries e ON e.path = k.path AND e.root_id = ?;
                """,
                [.int(rootID)]
            )
        }

        try exec("DROP TABLE IF EXISTS j4i_keep_text;")
        try exec("DROP TABLE IF EXISTS j4i_keep_embeddings;")
        embeddingCache = nil
        J4Log.info(.index, "Reindexado: re-vinculados \(textsToRestore) texto(s) y \(vectorsToRestore) vector(es) por ruta.")
        return Int(textsToRestore)
    }

    // MARK: - Búsqueda

    public func search(_ request: IndexSearchRequest) throws -> [IndexSearchHit] {
        try openIfNeeded()
        guard let match = request.matchExpression ?? Self.ftsMatchExpression(from: request.query) else { return [] }
        let limit = max(1, min(request.limit, 5_000))

        var hits: [IndexSearchHit] = []
        var seen = Set<Int64>()

        for (entry, rank) in try queryEntries(match: match, filters: request.filters, limit: limit) {
            hits.append(IndexSearchHit(entry: entry, score: rank, matchedContent: false, contentSnippet: nil))
            seen.insert(entry.id)
        }
        if request.includeContent {
            for (entry, rank, snippet) in try queryContent(match: match, filters: request.filters, limit: limit) {
                if seen.contains(entry.id) { continue }
                seen.insert(entry.id)
                hits.append(IndexSearchHit(entry: entry, score: rank, matchedContent: true, contentSnippet: snippet))
                if hits.count >= limit { break }
            }
        }
        // Pasada «contiene» (estilo Everything): si queda hueco en la página, busca la subcadena en
        // el nombre normalizado — «net» también encuentra «dotnet-sdk», «Internet…» o «Planet…».
        if hits.count < limit, request.matchExpression == nil, request.query.count >= 2 {
            for entry in try queryNameContains(request.query, filters: request.filters, limit: limit * 2, excluding: seen) {
                guard hits.count < limit else { break }
                seen.insert(entry.id)
                hits.append(IndexSearchHit(entry: entry, score: 1.0, matchedContent: false, contentSnippet: nil))
            }
        }
        if hits.count > limit {
            hits.removeLast(hits.count - limit)
        }
        return hits
    }

    /// N8 — Listado por filtros sin término de texto (`ext:pdf fecha:2026-09` a solas):
    /// entradas que cumplen los filtros, las más recientes primero (fecha de modificación).
    /// Sin MATCH: no hay término que buscar; el filtro es toda la consulta.
    public func listByFilters(filters: IndexSearchFilters, limit: Int = 300) throws -> [IndexSearchHit] {
        try openIfNeeded()
        let filterParts = filterClauses(filters)
        var sql = """
        SELECT e.id, e.root_id, e.path, e.name, e.ext, e.is_dir, e.size_bytes, e.modified_ts, 0.0
        FROM entries e
        """
        if !filterParts.clauses.isEmpty {
            sql += " WHERE " + filterParts.clauses.joined(separator: " AND ")
        }
        sql += " ORDER BY COALESCE(e.modified_ts, 0) DESC, e.id DESC LIMIT ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw sqliteError("No se pudo preparar el listado por filtros.")
        }
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, filterParts.binds + [.int(Int64(max(1, min(limit, 5_000))))])
        return try collectEntries(stmt).map {
            IndexSearchHit(entry: $0.0, score: $0.1, matchedContent: false, contentSnippet: nil)
        }
    }

    private func queryEntries(match: String, filters: IndexSearchFilters, limit: Int) throws -> [(IndexEntry, Double)] {
        let filterParts = filterClauses(filters)
        var sql = """
        SELECT e.id, e.root_id, e.path, e.name, e.ext, e.is_dir, e.size_bytes, e.modified_ts,
               bm25(entries_fts, 1.0, 5.0)
        FROM entries_fts
        JOIN entries e ON e.id = entries_fts.rowid
        WHERE entries_fts MATCH ?
        """
        if !filterParts.clauses.isEmpty {
            sql += " AND " + filterParts.clauses.joined(separator: " AND ")
        }
        sql += " ORDER BY bm25(entries_fts, 1.0, 5.0), length(e.path) ASC LIMIT ?;"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw sqliteError("No se pudo preparar búsqueda.")
        }
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, [.text(match)] + filterParts.binds + [.int(Int64(limit))])
        return try collectEntries(stmt)
    }

    private func queryContent(match: String, filters: IndexSearchFilters, limit: Int) throws -> [(entry: IndexEntry, rank: Double, snippet: String?)] {
        let filterParts = filterClauses(filters)
        var sql = """
        SELECT e.id, e.root_id, e.path, e.name, e.ext, e.is_dir, e.size_bytes, e.modified_ts,
               bm25(doc_text_fts),
               snippet(doc_text_fts, 0, '', '', '…', 16)
        FROM doc_text_fts
        JOIN doc_text d ON d.entry_id = doc_text_fts.rowid
        JOIN entries e ON e.id = d.entry_id
        WHERE doc_text_fts MATCH ?
        """
        if !filterParts.clauses.isEmpty {
            sql += " AND " + filterParts.clauses.joined(separator: " AND ")
        }
        sql += " ORDER BY bm25(doc_text_fts), length(e.path) ASC LIMIT ?;"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw sqliteError("No se pudo preparar búsqueda de contenido.")
        }
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, [.text(match)] + filterParts.binds + [.int(Int64(limit))])
        var results: [(entry: IndexEntry, rank: Double, snippet: String?)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let entry = makeEntry(from: stmt)
            let rank = sqlite3_column_double(stmt, 8)
            let cleaned = columnText(stmt, 9)?
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let snippet: String? = (cleaned?.isEmpty ?? true) ? nil : cleaned
            results.append((entry, rank, snippet))
        }
        return results
    }

    /// Entradas cuyo nombre normalizado contiene TODOS los sub-tokens de la consulta
    /// (búsqueda por subcadena; complemento del MATCH por prefijos de FTS5).
    private func queryNameContains(_ query: String, filters: IndexSearchFilters, limit: Int, excluding seen: Set<Int64>) throws -> [IndexEntry] {
        let tokens = Self.foldForContains(query)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return [] }

        let filterParts = filterClauses(filters)
        var clauses: [String] = ["e.name_norm IS NOT NULL"]
        var binds: [SQLBind] = []
        for token in tokens {
            clauses.append("e.name_norm LIKE ?")
            binds.append(.text("%\(token)%"))
        }
        if !filterParts.clauses.isEmpty {
            clauses.append(contentsOf: filterParts.clauses)
            binds.append(contentsOf: filterParts.binds)
        }
        let sql = """
        SELECT e.id, e.root_id, e.path, e.name, e.ext, e.is_dir, e.size_bytes, e.modified_ts, 0.0
        FROM entries e
        WHERE \(clauses.joined(separator: " AND "))
        ORDER BY length(e.name) ASC, e.path ASC LIMIT ?;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw sqliteError("No se pudo preparar búsqueda por subcadena.")
        }
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, binds + [.int(Int64(limit))])
        var results: [IndexEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let entry = makeEntry(from: stmt)
            if seen.contains(entry.id) { continue }
            results.append(entry)
        }
        return results
    }

    /// Normaliza texto para el cotejo por subcadena: minúsculas, sin diacríticos ni diferencias de ancho.
    static func foldForContains(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "es_ES"))
            .lowercased()
    }

    private func collectEntries(_ stmt: OpaquePointer?) throws -> [(IndexEntry, Double)] {
        var results: [(IndexEntry, Double)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let entry = makeEntry(from: stmt)
            let rank = sqlite3_column_double(stmt, 8)
            results.append((entry, rank))
        }
        return results
    }

    private func filterClauses(_ filters: IndexSearchFilters) -> (clauses: [String], binds: [SQLBind]) {
        var clauses: [String] = []
        var binds: [SQLBind] = []

        if let rootID = filters.rootID {
            clauses.append("e.root_id = ?")
            binds.append(.int(rootID))
        }
        if let exts = filters.extensions, !exts.isEmpty {
            clauses.append("e.is_dir = 0")
            let placeholders = Array(repeating: "?", count: exts.count).joined(separator: ", ")
            clauses.append("e.ext IN (\(placeholders))")
            for ext in exts.sorted() {
                binds.append(.text(ext.lowercased()))
            }
        }
        if let directoriesOnly = filters.directoriesOnly {
            clauses.append("e.is_dir = ?")
            binds.append(.int(directoriesOnly ? 1 : 0))
        }
        if let minSize = filters.minSizeBytes {
            clauses.append("e.size_bytes >= ?")
            binds.append(.int(minSize))
        }
        if let maxSize = filters.maxSizeBytes {
            clauses.append("e.size_bytes <= ?")
            binds.append(.int(maxSize))
        }
        if let after = filters.modifiedAfter {
            clauses.append("e.modified_ts IS NOT NULL AND e.modified_ts >= ?")
            binds.append(.double(after.timeIntervalSince1970))
        }
        if let before = filters.modifiedBefore {
            clauses.append("e.modified_ts IS NOT NULL AND e.modified_ts <= ?")
            binds.append(.double(before.timeIntervalSince1970))
        }
        if let prefix = filters.pathPrefix, !prefix.isEmpty {
            let std = URL(fileURLWithPath: prefix).standardizedFileURL.path
            let lo = std + "/"
            let hi = lo + "\u{10FFFF}"
            clauses.append("(e.path = ? OR (e.path >= ? AND e.path < ?))")
            binds.append(.text(std))
            binds.append(.text(lo))
            binds.append(.text(hi))
        }
        return (clauses, binds)
    }

    /// Construye una expresión MATCH de FTS5 con prefijos y AND explícito.
    ///
    /// Estrategia: trocear la query en sub-tokens alfanuméricos (mismo criterio que el
    /// tokenizador unicode61), de modo que ningún carácter con significado sintáctico en
    /// FTS5 (`" * ( ) : ^ ~ -`) llegue a la expresión MATCH.
    /// Ej.: `informe-2026` → `informe* AND 2026*`.
    static func ftsMatchExpression(from query: String) -> String? {
        let rawTerms = query.lowercased().split(whereSeparator: { $0.isWhitespace })
        var terms: [String] = []
        for raw in rawTerms {
            let subTokens = raw.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            for sub in subTokens {
                let term = String(sub)
                guard !term.isEmpty else { continue }
                if ["and", "or", "not", "near"].contains(term) { continue }
                terms.append("\(term)*")
            }
        }
        guard !terms.isEmpty else { return nil }
        return terms.joined(separator: " AND ")
    }

    // MARK: - Cache de análisis

    public func loadCachedAnalysis(hash: String) throws -> CachedAnalysis? {
        try openIfNeeded()
        let sql = "SELECT profile_json, proposal_json, filed_path FROM analysis_cache WHERE hash = ? LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw sqliteError("No se pudo preparar consulta de cache.")
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, hash, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return CachedAnalysis(
            profileJSON: columnText(stmt, 0),
            proposalJSON: columnText(stmt, 1),
            filedPath: columnText(stmt, 2)
        )
    }

    public func storeCachedAnalysis(hash: String, profileJSON: String?, proposalJSON: String?) throws {
        try openIfNeeded()
        try exec(
            """
            INSERT INTO analysis_cache(hash, profile_json, proposal_json, filed_path, updated_ts)
            VALUES(?, ?, ?, NULL, ?)
            ON CONFLICT(hash) DO UPDATE SET
                profile_json = excluded.profile_json,
                proposal_json = COALESCE(excluded.proposal_json, analysis_cache.proposal_json),
                updated_ts = excluded.updated_ts;
            """,
            [
                .text(hash),
                profileJSON.map { SQLBind.text($0) } ?? .null,
                proposalJSON.map { SQLBind.text($0) } ?? .null,
                .double(Date().timeIntervalSince1970)
            ]
        )
    }

    public func updateCachedFiledPath(hash: String, filedPath: String) throws {
        try openIfNeeded()
        try exec(
            "UPDATE analysis_cache SET filed_path = ?, updated_ts = ? WHERE hash = ?;",
            [.text(filedPath), .double(Date().timeIntervalSince1970), .text(hash)]
        )
    }

    /// Repunta una entrada de caché de archivo al mover un documento (p. ej. archivo en frío, G6)
    /// sin recalcular el hash: la detección de duplicados sigue apuntando al sitio correcto.
    public func repointCachedFiledPath(from oldPath: String, to newPath: String) throws {
        try openIfNeeded()
        try exec(
            "UPDATE analysis_cache SET filed_path = ?, updated_ts = ? WHERE filed_path = ?;",
            [.text(newPath), .double(Date().timeIntervalSince1970), .text(oldPath)]
        )
    }

    // MARK: - Journal de operaciones

    @discardableResult
    public func journalAppend(
        batchID: String,
        sourcePath: String,
        destinationPath: String,
        categoryPath: String,
        action: String,
        state: String = "applied"
    ) throws -> Int64 {
        try openIfNeeded()
        try exec(
            """
            INSERT INTO ops_journal(ts, batch_id, src_path, dst_path, category_path, action, state)
            VALUES(?, ?, ?, ?, ?, ?, ?);
            """,
            [
                .double(Date().timeIntervalSince1970),
                .text(batchID),
                .text(sourcePath),
                .text(destinationPath),
                .text(categoryPath),
                .text(action),
                .text(state)
            ]
        )
        return sqlite3_last_insert_rowid(db)
    }

    public func journalRecent(limit: Int = 50) throws -> [JournalEntry] {
        try openIfNeeded()
        let sql = "SELECT id, ts, batch_id, src_path, dst_path, category_path, action, state, undone_ts FROM ops_journal ORDER BY id DESC LIMIT ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw sqliteError("No se pudo preparar consulta del journal.")
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, Int64(max(1, min(limit, 1000))))
        var entries: [JournalEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            entries.append(makeJournalEntry(from: stmt))
        }
        return entries
    }

    /// Entradas del journal dentro de un rango temporal (informe semanal, G6).
    public func journalEntries(since: Date, until: Date = Date(), limit: Int = 5000) throws -> [JournalEntry] {
        try openIfNeeded()
        let sql = "SELECT id, ts, batch_id, src_path, dst_path, category_path, action, state, undone_ts FROM ops_journal WHERE ts >= ? AND ts <= ? ORDER BY id DESC LIMIT ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw sqliteError("No se pudo preparar la consulta del journal por rango.")
        }
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, [.double(since.timeIntervalSince1970), .double(until.timeIntervalSince1970), .int(Int64(max(1, limit)))])
        var entries: [JournalEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            entries.append(makeJournalEntry(from: stmt))
        }
        return entries
    }

    public func journalEntry(id: Int64) throws -> JournalEntry? {
        try openIfNeeded()
        let sql = "SELECT id, ts, batch_id, src_path, dst_path, category_path, action, state, undone_ts FROM ops_journal WHERE id = ? LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw sqliteError("No se pudo preparar consulta del journal.")
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, id)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return makeJournalEntry(from: stmt)
    }

    public func journalMarkUndone(id: Int64) throws {
        try openIfNeeded()
        try exec("UPDATE ops_journal SET state = 'undone', undone_ts = ? WHERE id = ?;", [.double(Date().timeIntervalSince1970), .int(id)])
    }

    public func journalLatestBatchID() throws -> String? {
        try openIfNeeded()
        let sql = "SELECT batch_id FROM ops_journal ORDER BY id DESC LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw sqliteError("No se pudo preparar consulta del journal.")
        }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return columnText(stmt, 0)
    }

    private func makeJournalEntry(from stmt: OpaquePointer?) -> JournalEntry {
        let undoneAt = sqlite3_column_type(stmt, 8) == SQLITE_NULL
            ? nil
            : Date(timeIntervalSince1970: sqlite3_column_double(stmt, 8))
        return JournalEntry(
            id: sqlite3_column_int64(stmt, 0),
            timestamp: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1)),
            batchID: columnText(stmt, 2) ?? "",
            sourcePath: columnText(stmt, 3) ?? "",
            destinationPath: columnText(stmt, 4) ?? "",
            categoryPath: columnText(stmt, 5) ?? "",
            action: columnText(stmt, 6) ?? "",
            state: columnText(stmt, 7) ?? "applied",
            undoneAt: undoneAt
        )
    }

    // MARK: - Helpers de entradas

    public func entryID(path: String) throws -> Int64? {
        try openIfNeeded()
        let std = URL(fileURLWithPath: path).standardizedFileURL.path
        return try scalarInt64("SELECT id FROM entries WHERE path = ? LIMIT 1;", [.text(std)])
    }

    public func rootID(containing path: String) throws -> (id: Int64, path: String)? {
        let std = URL(fileURLWithPath: path).standardizedFileURL.path
        let roots = try allRoots()
        guard let root = roots.first(where: { std == $0.path || std.hasPrefix($0.path + "/") }) else {
            return nil
        }
        return (root.id, root.path)
    }

    // MARK: - Conteos

    public func entryCount(rootID: Int64? = nil) throws -> Int64 {
        try openIfNeeded()
        if let rootID {
            return try scalarInt64("SELECT COUNT(*) FROM entries WHERE root_id = ?;", [.int(rootID)]) ?? 0
        }
        return try scalarInt64("SELECT COUNT(*) FROM entries;", []) ?? 0
    }

    public func stats() throws -> IndexStats {
        try openIfNeeded()
        let total = try scalarInt64("SELECT COUNT(*) FROM entries;", []) ?? 0
        let dirs = try scalarInt64("SELECT COUNT(*) FROM entries WHERE is_dir = 1;", []) ?? 0
        return IndexStats(totalEntries: total, totalFiles: total - dirs, totalDirectories: dirs)
    }

    /// Hijos directos de una carpeta (subcarpetas y ficheros), ordenados: carpetas primero,
    /// luego por nombre (case-insensitive). No incluye nietos. Lo usa el explorador.
    public func children(ofDirectory path: String) throws -> [IndexEntry] {
        try openIfNeeded()
        let std = URL(fileURLWithPath: path).standardizedFileURL.path
        let sql = """
            SELECT id, root_id, path, name, ext, is_dir, size_bytes, modified_ts
            FROM entries
            WHERE parent_path = ?
            ORDER BY is_dir DESC, name COLLATE NOCASE ASC;
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw sqliteError("No se pudo preparar la consulta de hijos.")
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, std, -1, SQLITE_TRANSIENT)
        var result: [IndexEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            result.append(makeEntry(from: stmt))
        }
        return result
    }

    /// Estadísticas del subárbol de una carpeta: ficheros visibles, subcarpetas y tamaño total.
    ///
    /// `fileCount` excluye archivos ocultos (`.DS_Store`, …) para que una carpeta con solo
    /// ocultos cuente como vacía (filtro del explorador).
    public func subtreeStats(forDirectory path: String) throws -> DirectoryStats {
        try openIfNeeded()
        let std = URL(fileURLWithPath: path).standardizedFileURL.path
        let lo = std + "/"
        let hi = lo + "\u{10FFFF}"
        let fileCount = try scalarInt64(
            "SELECT COUNT(*) FROM entries WHERE path >= ? AND path < ? AND is_dir = 0 AND substr(name, 1, 1) <> '.';",
            [.text(lo), .text(hi)]
        ) ?? 0
        let directoryCount = try scalarInt64(
            "SELECT COUNT(*) FROM entries WHERE path >= ? AND path < ? AND is_dir = 1;",
            [.text(lo), .text(hi)]
        ) ?? 0
        let totalSize = try scalarInt64(
            "SELECT COALESCE(SUM(size_bytes), 0) FROM entries WHERE path >= ? AND path < ? AND is_dir = 0 AND substr(name, 1, 1) <> '.';",
            [.text(lo), .text(hi)]
        ) ?? 0
        return DirectoryStats(fileCount: fileCount, directoryCount: directoryCount, totalSizeBytes: totalSize)
    }

    public func optimize() throws {
        try openIfNeeded()
        try exec("INSERT INTO entries_fts(entries_fts) VALUES('optimize');")
        try exec("INSERT INTO doc_text_fts(doc_text_fts) VALUES('optimize');")
    }

    // MARK: - Internals: schema

    private func openIfNeeded() throws {
        guard !didOpen else { return }
        let folder = dbURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var handle: OpaquePointer?
        guard sqlite3_open(dbURL.path, &handle) == SQLITE_OK, let handle else {
            throw IndexError.openFailed("No se pudo abrir la base del índice (\(dbURL.path)).")
        }
        db = handle
        didOpen = true

        try exec("PRAGMA journal_mode = WAL;")
        try exec("PRAGMA synchronous = NORMAL;")
        try exec("PRAGMA temp_store = MEMORY;")
        try exec("PRAGMA busy_timeout = 3000;")
        try migrateIfNeeded()
    }

    private func migrateIfNeeded() throws {
        let version = try scalarInt64("PRAGMA user_version;", []) ?? 0
        if version < 1 {
            try applySchemaV1()
        }
        if version < 2 {
            try applySchemaV2()
        }
        if version < 3 {
            try applySchemaV3()
        }
        if version < 4 {
            try applySchemaV4()
        }
        if version != Int64(Self.schemaVersion) {
            try exec("PRAGMA user_version = \(Self.schemaVersion);")
        }
    }

    /// v3: columna `name_norm` (nombre en minúsculas y sin diacríticos) para la búsqueda por
    /// subcadena estilo «Everything»: «net» encuentra «dotnet-sdk» o «Internet…», no solo «NetBSD».
    private func applySchemaV3() throws {
        try exec("ALTER TABLE entries ADD COLUMN name_norm TEXT;")
        try backfillNameNorm()
    }

    private func backfillNameNorm() throws {
        while true {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT id, name FROM entries WHERE name_norm IS NULL LIMIT 1000;", -1, &stmt, nil) == SQLITE_OK else {
                throw sqliteError("No se pudo preparar el rellenado de name_norm.")
            }
            var rows: [(id: Int64, name: String)] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let name = columnText(stmt, 1) {
                    rows.append((sqlite3_column_int64(stmt, 0), name))
                }
            }
            sqlite3_finalize(stmt)
            if rows.isEmpty { break }
            try inTransaction {
                for row in rows {
                    try exec("UPDATE entries SET name_norm = ? WHERE id = ?;", [.text(Self.foldForContains(row.name)), .int(row.id)])
                }
            }
        }
    }

    private func applySchemaV1() throws {
        try exec(
            """
            CREATE TABLE IF NOT EXISTS roots (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                path TEXT NOT NULL UNIQUE,
                added_ts REAL NOT NULL,
                state TEXT NOT NULL DEFAULT 'pending',
                last_event_id INTEGER,
                scanned_count INTEGER NOT NULL DEFAULT 0,
                last_crawl_ts REAL
            );
            """
        )
        try exec(
            """
            CREATE TABLE IF NOT EXISTS entries (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                root_id INTEGER NOT NULL,
                path TEXT NOT NULL UNIQUE,
                parent_path TEXT NOT NULL,
                name TEXT NOT NULL,
                ext TEXT NOT NULL,
                is_dir INTEGER NOT NULL,
                size_bytes INTEGER NOT NULL,
                modified_ts REAL,
                created_ts REAL
            );
            """
        )
        try exec("CREATE INDEX IF NOT EXISTS idx_entries_root ON entries(root_id);")
        try exec("CREATE INDEX IF NOT EXISTS idx_entries_parent ON entries(parent_path);")
        try exec("CREATE INDEX IF NOT EXISTS idx_entries_ext ON entries(ext);")
        try exec(
            """
            CREATE VIRTUAL TABLE IF NOT EXISTS entries_fts
            USING fts5(path, name, tokenize='unicode61 remove_diacritics 2');
            """
        )
        try exec(
            """
            CREATE TABLE IF NOT EXISTS doc_text (
                entry_id INTEGER PRIMARY KEY,
                text TEXT NOT NULL,
                updated_ts REAL NOT NULL
            );
            """
        )
        try exec(
            """
            CREATE VIRTUAL TABLE IF NOT EXISTS doc_text_fts
            USING fts5(text, tokenize='unicode61 remove_diacritics 2');
            """
        )
    }

    private func applySchemaV2() throws {
        try exec(
            """
            CREATE TABLE IF NOT EXISTS analysis_cache (
                hash TEXT PRIMARY KEY,
                profile_json TEXT,
                proposal_json TEXT,
                filed_path TEXT,
                updated_ts REAL NOT NULL
            );
            """
        )
        try exec(
            """
            CREATE TABLE IF NOT EXISTS ops_journal (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                ts REAL NOT NULL,
                batch_id TEXT NOT NULL,
                src_path TEXT NOT NULL,
                dst_path TEXT NOT NULL,
                category_path TEXT NOT NULL,
                action TEXT NOT NULL,
                state TEXT NOT NULL DEFAULT 'applied',
                undone_ts REAL
            );
            """
        )
        try exec("CREATE INDEX IF NOT EXISTS idx_journal_batch ON ops_journal(batch_id);")
        try exec("CREATE INDEX IF NOT EXISTS idx_journal_ts ON ops_journal(ts);")
    }

    /// v4 (G7): vectores semánticos locales por entrada (`embeddings`). Se guarda el modelo y la
    /// fuente ('name' o 'content') para poder re-vectorizar cuando llegue el texto del documento
    /// o cuando cambie el modelo de embeddings.
    private func applySchemaV4() throws {
        try exec(
            """
            CREATE TABLE IF NOT EXISTS embeddings (
                entry_id INTEGER PRIMARY KEY,
                model TEXT NOT NULL,
                dim INTEGER NOT NULL,
                source TEXT NOT NULL DEFAULT 'name',
                vec BLOB NOT NULL,
                updated_ts REAL NOT NULL
            );
            """
        )
        // Barrido de vectores huérfanos (entradas que ya no existen; p. ej. de antes del esquema).
        try exec("DELETE FROM embeddings WHERE entry_id NOT IN (SELECT id FROM entries);")
    }

    // MARK: - Internals: helpers

    private func fetchRoot(path: String) throws -> IndexRoot? {
        let sql = "SELECT id, path, added_ts FROM roots WHERE path = ? LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw sqliteError("No se pudo preparar consulta de root.")
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, path, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return makeRoot(from: stmt)
    }

    private func makeRoot(from stmt: OpaquePointer?) -> IndexRoot {
        IndexRoot(
            id: sqlite3_column_int64(stmt, 0),
            path: columnText(stmt, 1) ?? "",
            addedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2))
        )
    }

    private func makeEntry(from stmt: OpaquePointer?) -> IndexEntry {
        let modified: Date? = sqlite3_column_type(stmt, 7) == SQLITE_NULL
            ? nil
            : Date(timeIntervalSince1970: sqlite3_column_double(stmt, 7))
        return IndexEntry(
            id: sqlite3_column_int64(stmt, 0),
            rootID: sqlite3_column_int64(stmt, 1),
            path: columnText(stmt, 2) ?? "",
            name: columnText(stmt, 3) ?? "",
            ext: columnText(stmt, 4) ?? "",
            isDirectory: sqlite3_column_int(stmt, 5) != 0,
            sizeBytes: sqlite3_column_int64(stmt, 6),
            modifiedAt: modified
        )
    }

    private func countEntries(rootID: Int64, path: String, lo: String, hi: String) throws -> Int {
        let sql = "SELECT COUNT(*) FROM entries WHERE root_id = ? AND (path = ? OR (path >= ? AND path < ?));"
        return Int(try scalarInt64(sql, [.int(rootID), .text(path), .text(lo), .text(hi)]) ?? 0)
    }

    private func deleteEntriesSQL(rootID: Int64) throws {
        try exec("DELETE FROM doc_text_fts WHERE rowid IN (SELECT id FROM entries WHERE root_id = ?);", [.int(rootID)])
        try exec("DELETE FROM doc_text WHERE entry_id IN (SELECT id FROM entries WHERE root_id = ?);", [.int(rootID)])
        try exec("DELETE FROM embeddings WHERE entry_id IN (SELECT id FROM entries WHERE root_id = ?);", [.int(rootID)])
        try exec("DELETE FROM entries_fts WHERE rowid IN (SELECT id FROM entries WHERE root_id = ?);", [.int(rootID)])
        try exec("DELETE FROM entries WHERE root_id = ?;", [.int(rootID)])
    }

    private func deleteFTSRows(paths: [String]) throws {
        for path in paths {
            try exec(
                "DELETE FROM entries_fts WHERE rowid IN (SELECT id FROM entries WHERE path = ?);",
                [.text(path)]
            )
        }
    }

    private func documentTextForPath(_ path: String) throws -> String? {
        let sql = "SELECT dt.text FROM doc_text dt JOIN entries e ON e.id = dt.entry_id WHERE e.path = ? LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw sqliteError("No se pudo preparar la lectura de texto por ruta.")
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, path, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return columnText(stmt, 0)
    }

    private func embeddingForPath(_ path: String) throws -> (model: String, dim: Int, source: String, vec: Data)? {
        let sql = "SELECT em.model, em.dim, em.source, em.vec FROM embeddings em JOIN entries e ON e.id = em.entry_id WHERE e.path = ? LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw sqliteError("No se pudo preparar la lectura de embeddings por ruta.")
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, path, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        guard let model = columnText(stmt, 0), let source = columnText(stmt, 2), let vec = columnBlob(stmt, 3) else {
            return nil
        }
        return (model, Int(sqlite3_column_int64(stmt, 1)), source, vec)
    }

    private func inTransaction(_ body: () throws -> Void) throws {
        try exec("BEGIN IMMEDIATE TRANSACTION;")
        do {
            try body()
            try exec("COMMIT;")
        } catch {
            try? exec("ROLLBACK;")
            throw error
        }
    }

    private func scalarInt64(_ sql: String, _ binds: [SQLBind]) throws -> Int64? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw sqliteError("No se pudo preparar consulta escalar.")
        }
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, binds)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        if sqlite3_column_type(stmt, 0) == SQLITE_NULL { return nil }
        return sqlite3_column_int64(stmt, 0)
    }

    private func exec(_ sql: String, _ binds: [SQLBind] = []) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw sqliteError("No se pudo preparar SQL.")
        }
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, binds)
        let rc = sqlite3_step(stmt)
        if rc != SQLITE_DONE && rc != SQLITE_ROW {
            throw sqliteError("Fallo ejecutando SQL.")
        }
    }

    private func bind(_ stmt: OpaquePointer?, _ binds: [SQLBind]) throws {
        guard let stmt else { throw IndexError.sqlFailed("Sentencia sin conexión.") }
        for (offset, value) in binds.enumerated() {
            let slot = Int32(offset + 1)
            switch value {
            case .text(let s):
                sqlite3_bind_text(stmt, slot, s, -1, SQLITE_TRANSIENT)
            case .int(let i):
                sqlite3_bind_int64(stmt, slot, sqlite3_int64(i))
            case .double(let d):
                sqlite3_bind_double(stmt, slot, d)
            case .blob(let data):
                _ = data.withUnsafeBytes { buffer in
                    sqlite3_bind_blob(stmt, slot, buffer.baseAddress, Int32(data.count), SQLITE_TRANSIENT)
                }
            case .null:
                sqlite3_bind_null(stmt, slot)
            }
        }
    }

    private func columnText(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let cString = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: cString)
    }

    private func columnBlob(_ stmt: OpaquePointer?, _ index: Int32) -> Data? {
        guard let pointer = sqlite3_column_blob(stmt, index) else { return nil }
        let count = Int(sqlite3_column_bytes(stmt, index))
        guard count > 0 else { return nil }
        return Data(bytes: pointer, count: count)
    }

    private func sqliteError(_ fallback: String) -> IndexError {
        let message = db.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? fallback
        return .sqlFailed(message)
    }
}

enum SQLBind {
    case text(String)
    case int(Int64)
    case double(Double)
    case blob(Data)
    case null
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
