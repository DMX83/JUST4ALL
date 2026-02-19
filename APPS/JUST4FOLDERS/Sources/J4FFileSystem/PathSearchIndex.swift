import Foundation
import SQLite3

public struct PathIndexHit: Hashable {
    public let path: String
    public let name: String
    public let isDirectory: Bool
    public let sizeBytes: Int64
    public let modifiedTimeInterval: TimeInterval

    public init(path: String, name: String, isDirectory: Bool, sizeBytes: Int64, modifiedTimeInterval: TimeInterval) {
        self.path = path
        self.name = name
        self.isDirectory = isDirectory
        self.sizeBytes = sizeBytes
        self.modifiedTimeInterval = modifiedTimeInterval
    }
}

public actor PathSearchIndex {
    public static let shared = PathSearchIndex()

    private let dbURL: URL
    private var db: OpaquePointer?
    private var didOpen = false

    public init(databaseURL: URL? = nil) {
        if let databaseURL {
            self.dbURL = databaseURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            let base = appSupport.appendingPathComponent("JUST4FOLDERS", isDirectory: true)
            self.dbURL = base.appendingPathComponent("path-index.sqlite", isDirectory: false)
        }
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    public func ensureIndexed(roots: [URL], includeHidden: Bool) async throws {
        try openIfNeeded()
        let uniqueRoots = Array(Set(roots.map { $0.standardizedFileURL.path })).sorted()
        for rootPath in uniqueRoots {
            let root = URL(fileURLWithPath: rootPath, isDirectory: true)
            if try hasAnyEntriesUnderPath(root.path) {
                continue
            }
            try indexRoot(root, includeHidden: includeHidden, replaceExistingRoot: false)
        }
    }

    public func forceReindex(roots: [URL], includeHidden: Bool) async throws {
        try openIfNeeded()
        let uniqueRoots = Array(Set(roots.map { $0.standardizedFileURL.path })).sorted()
        for rootPath in uniqueRoots {
            let root = URL(fileURLWithPath: rootPath, isDirectory: true)
            try indexRoot(root, includeHidden: includeHidden, replaceExistingRoot: true)
        }
    }

    public func ensureIndexedCooperative(
        roots: [URL],
        includeHidden: Bool,
        batchSize: Int = 400,
        pausePerBatchMS: UInt64 = 20
    ) async throws {
        try openIfNeeded()
        let uniqueRoots = Array(Set(roots.map { $0.standardizedFileURL.path })).sorted()
        for rootPath in uniqueRoots {
            try Task.checkCancellation()
            let root = URL(fileURLWithPath: rootPath, isDirectory: true)
            guard isDirectory(root) else { continue }
            if try hasAnyEntriesUnderPath(root.path) {
                continue
            }
            try await indexRootCooperative(
                root,
                includeHidden: includeHidden,
                replaceExistingRoot: false,
                batchSize: max(100, batchSize),
                pausePerBatchMS: pausePerBatchMS
            )
        }
    }

    public func isIndexed(for root: URL) async -> Bool {
        do {
            try openIfNeeded()
            return try hasAnyEntriesUnderPath(root.standardizedFileURL.path)
        } catch {
            return false
        }
    }

    public func search(query: String, under root: URL, limit: Int = 5000) async throws -> [PathIndexHit] {
        try openIfNeeded()
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return [] }

        let terms = clean
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !terms.isEmpty else { return [] }

        let match = terms.map { term in
            let sanitized = term.replacingOccurrences(of: "\"", with: "")
            return "\(sanitized)*"
        }.joined(separator: " AND ")

        let rootPath = root.standardizedFileURL.path
        let rootPrefix = rootPath.hasSuffix("/") ? "\(rootPath)%" : "\(rootPath)/%"
        let sql = """
        SELECT e.path, e.name, e.is_dir, e.size_bytes, e.modified_ts
        FROM entries_fts f
        JOIN entries e ON e.path = f.path
        WHERE f.name MATCH ?
          AND (e.path = ? OR e.path LIKE ?)
        ORDER BY bm25(f), length(e.path) ASC
        LIMIT ?;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw sqliteError("No se pudo preparar busqueda indexada.")
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, match, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, rootPath, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 3, rootPrefix, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(statement, 4, Int32(max(1, min(50_000, limit))))

        var hits: [PathIndexHit] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let cPath = sqlite3_column_text(statement, 0),
                let cName = sqlite3_column_text(statement, 1)
            else { continue }

            let path = String(cString: cPath)
            let name = String(cString: cName)
            let isDir = sqlite3_column_int(statement, 2) != 0
            let size = sqlite3_column_int64(statement, 3)
            let modified = sqlite3_column_double(statement, 4)
            hits.append(
                PathIndexHit(
                    path: path,
                    name: name,
                    isDirectory: isDir,
                    sizeBytes: size,
                    modifiedTimeInterval: modified
                )
            )
        }

        return hits
    }

    public func refreshChangedPaths(_ changedPaths: [String], watchedRoot: URL, includeHidden: Bool) async {
        do {
            try openIfNeeded()
            let root = watchedRoot.standardizedFileURL
            for raw in changedPaths {
                let changed = URL(fileURLWithPath: raw).standardizedFileURL
                let changedPath = changed.path
                if !(changedPath == root.path || changedPath.hasPrefix(root.path + "/")) {
                    continue
                }
                try deleteEntriesUnderPath(changedPath)
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: changedPath, isDirectory: &isDir) {
                    if isDir.boolValue {
                        try indexRoot(changed, includeHidden: includeHidden, replaceExistingRoot: false)
                    } else {
                        try upsertSingleFile(changed, rootPath: root.path, includeHidden: includeHidden)
                    }
                }
            }
        } catch {
            // best-effort refresh, ignore failures to keep UI responsive
        }
    }

    private func openIfNeeded() throws {
        guard !didOpen else { return }
        let folder = dbURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var handle: OpaquePointer?
        guard sqlite3_open(dbURL.path, &handle) == SQLITE_OK, let handle else {
            throw sqliteError("No se pudo abrir base de indice.")
        }
        db = handle
        didOpen = true

        try exec("PRAGMA journal_mode = WAL;")
        try exec("PRAGMA synchronous = NORMAL;")
        try exec("PRAGMA temp_store = MEMORY;")
        try bootstrapSchema()
    }

    private func bootstrapSchema() throws {
        try exec(
            """
            CREATE TABLE IF NOT EXISTS entries (
                path TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                parent_path TEXT NOT NULL,
                is_dir INTEGER NOT NULL,
                size_bytes INTEGER NOT NULL,
                modified_ts REAL NOT NULL
            );
            """
        )
        try exec("CREATE INDEX IF NOT EXISTS idx_entries_parent ON entries(parent_path);")
        try exec("CREATE INDEX IF NOT EXISTS idx_entries_name ON entries(name);")
        try exec(
            """
            CREATE VIRTUAL TABLE IF NOT EXISTS entries_fts
            USING fts5(path, name, tokenize='unicode61 remove_diacritics 2');
            """
        )
    }

    private func indexRoot(_ root: URL, includeHidden: Bool, replaceExistingRoot: Bool) throws {
        let rootPath = root.standardizedFileURL.path
        if replaceExistingRoot {
            try deleteEntriesUnderPath(rootPath)
        }

        try exec("BEGIN IMMEDIATE TRANSACTION;")
        do {
            try upsertDirectory(root, includeHidden: includeHidden)
            let keys: Set<URLResourceKey> = [
                .isDirectoryKey,
                .isRegularFileKey,
                .isHiddenKey,
                .fileSizeKey,
                .contentModificationDateKey
            ]

            if let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsPackageDescendants]
            ) {
                while let next = enumerator.nextObject() {
                    guard let url = next as? URL else { continue }
                    let values = try? url.resourceValues(forKeys: keys)
                    if !includeHidden, values?.isHidden == true {
                        if values?.isDirectory == true {
                            enumerator.skipDescendants()
                        }
                        continue
                    }
                    if values?.isDirectory == true {
                        try upsertDirectory(url, includeHidden: includeHidden)
                    } else if values?.isRegularFile == true {
                        try upsertSingleFile(url, rootPath: rootPath, includeHidden: includeHidden)
                    }
                }
            }

            try exec("COMMIT;")
        } catch {
            try? exec("ROLLBACK;")
            throw error
        }
    }

    private func indexRootCooperative(
        _ root: URL,
        includeHidden: Bool,
        replaceExistingRoot: Bool,
        batchSize: Int,
        pausePerBatchMS: UInt64
    ) async throws {
        let rootPath = root.standardizedFileURL.path
        if replaceExistingRoot {
            try deleteEntriesUnderPath(rootPath)
        }

        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isHiddenKey,
            .fileSizeKey,
            .contentModificationDateKey
        ]

        try exec("BEGIN IMMEDIATE TRANSACTION;")
        do {
            try upsertDirectory(root, includeHidden: includeHidden)
            var operationsInBatch = 1

            if let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsPackageDescendants]
            ) {
                while let next = enumerator.nextObject() {
                    try Task.checkCancellation()
                    guard let url = next as? URL else { continue }
                    let values = try? url.resourceValues(forKeys: keys)
                    if !includeHidden, values?.isHidden == true {
                        if values?.isDirectory == true {
                            enumerator.skipDescendants()
                        }
                        continue
                    }
                    if values?.isDirectory == true {
                        try upsertDirectory(url, includeHidden: includeHidden)
                        operationsInBatch += 1
                    } else if values?.isRegularFile == true {
                        try upsertSingleFile(url, rootPath: rootPath, includeHidden: includeHidden)
                        operationsInBatch += 1
                    }

                    if operationsInBatch >= batchSize {
                        try exec("COMMIT;")
                        await Task.yield()
                        if pausePerBatchMS > 0 {
                            try? await Task.sleep(nanoseconds: pausePerBatchMS * 1_000_000)
                        }
                        try exec("BEGIN IMMEDIATE TRANSACTION;")
                        operationsInBatch = 0
                    }
                }
            }

            try exec("COMMIT;")
        } catch {
            try? exec("ROLLBACK;")
            throw error
        }
    }

    private func upsertDirectory(_ url: URL, includeHidden: Bool) throws {
        let keys: Set<URLResourceKey> = [.isHiddenKey, .contentModificationDateKey]
        let values = try url.resourceValues(forKeys: keys)
        if !includeHidden, values.isHidden == true {
            return
        }
        let modified = values.contentModificationDate?.timeIntervalSince1970 ?? 0
        try upsertEntry(
            path: url.standardizedFileURL.path,
            name: url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent,
            parentPath: url.deletingLastPathComponent().standardizedFileURL.path,
            isDirectory: true,
            sizeBytes: 0,
            modifiedTS: modified
        )
    }

    private func upsertSingleFile(_ url: URL, rootPath: String, includeHidden: Bool) throws {
        let keys: Set<URLResourceKey> = [.isHiddenKey, .fileSizeKey, .contentModificationDateKey]
        let values = try url.resourceValues(forKeys: keys)
        if !includeHidden, values.isHidden == true {
            return
        }
        let modified = values.contentModificationDate?.timeIntervalSince1970 ?? 0
        try upsertEntry(
            path: url.standardizedFileURL.path,
            name: url.lastPathComponent,
            parentPath: url.deletingLastPathComponent().standardizedFileURL.path,
            isDirectory: false,
            sizeBytes: Int64(values.fileSize ?? 0),
            modifiedTS: modified
        )
    }

    private func upsertEntry(path: String, name: String, parentPath: String, isDirectory: Bool, sizeBytes: Int64, modifiedTS: TimeInterval) throws {
        try exec("DELETE FROM entries WHERE path = ?;", [path])
        try exec("DELETE FROM entries_fts WHERE path = ?;", [path])
        try exec(
            """
            INSERT INTO entries(path, name, parent_path, is_dir, size_bytes, modified_ts)
            VALUES(?, ?, ?, ?, ?, ?);
            """,
            [path, name, parentPath, isDirectory ? 1 : 0, sizeBytes, modifiedTS]
        )
        try exec("INSERT INTO entries_fts(path, name) VALUES(?, ?);", [path, name])
    }

    private func hasAnyEntriesUnderPath(_ path: String) throws -> Bool {
        let prefix = path.hasSuffix("/") ? "\(path)%" : "\(path)/%"
        let sql = "SELECT 1 FROM entries WHERE path = ? OR path LIKE ? LIMIT 1;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw sqliteError("No se pudo preparar consulta de indice.")
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, path, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, prefix, -1, SQLITE_TRANSIENT)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private func deleteEntriesUnderPath(_ path: String) throws {
        let prefix = path.hasSuffix("/") ? "\(path)%" : "\(path)/%"
        try exec("DELETE FROM entries_fts WHERE path = ? OR path LIKE ?;", [path, prefix])
        try exec("DELETE FROM entries WHERE path = ? OR path LIKE ?;", [path, prefix])
    }

    private func exec(_ sql: String, _ params: [Any] = []) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw sqliteError("No se pudo preparar SQL.")
        }
        defer { sqlite3_finalize(statement) }

        for (idx, value) in params.enumerated() {
            let slot = Int32(idx + 1)
            switch value {
            case let s as String:
                sqlite3_bind_text(statement, slot, s, -1, SQLITE_TRANSIENT)
            case let i as Int:
                sqlite3_bind_int64(statement, slot, sqlite3_int64(i))
            case let i64 as Int64:
                sqlite3_bind_int64(statement, slot, sqlite3_int64(i64))
            case let d as Double:
                sqlite3_bind_double(statement, slot, d)
            case let t as TimeInterval:
                sqlite3_bind_double(statement, slot, t)
            default:
                sqlite3_bind_null(statement, slot)
            }
        }

        let rc = sqlite3_step(statement)
        if rc != SQLITE_DONE && rc != SQLITE_ROW {
            throw sqliteError("Fallo ejecutando SQL.")
        }
    }

    private func sqliteError(_ fallback: String) -> NSError {
        let message = db.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? fallback
        return NSError(domain: "J4FFileSystem.PathSearchIndex", code: 5001, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
