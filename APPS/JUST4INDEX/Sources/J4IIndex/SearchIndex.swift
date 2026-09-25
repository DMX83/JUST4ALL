import Foundation
import SQLite3

/// Índice local de JUST4INDEX (SQLite + FTS5).
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

    public static let schemaVersion: Int32 = 3

    private let dbURL: URL
    private var db: OpaquePointer?
    private var didOpen = false

    public init(databaseURL: URL? = nil) {
        if let databaseURL {
            self.dbURL = databaseURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            let base = appSupport.appendingPathComponent("JUST4INDEX", isDirectory: true)
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
                try deleteFTSRows(paths: [entry.path])
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
                written += 1
            }
        }
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

    // MARK: - Búsqueda

    public func search(_ request: IndexSearchRequest) throws -> [IndexSearchHit] {
        try openIfNeeded()
        guard let match = Self.ftsMatchExpression(from: request.query) else { return [] }
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
        if hits.count < limit, request.query.count >= 2 {
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
            case .null:
                sqlite3_bind_null(stmt, slot)
            }
        }
    }

    private func columnText(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let cString = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: cString)
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
    case null
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
