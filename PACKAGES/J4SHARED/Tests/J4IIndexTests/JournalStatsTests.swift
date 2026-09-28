import XCTest
@testable import J4IIndex

/// N7 — agregados del journal (`journalStats`) y columna `source` del esquema v5.
final class JournalStatsTests: XCTestCase {
    private var tempDir: URL!
    private var index: SearchIndex!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("j4i-stats-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        index = SearchIndex(databaseURL: tempDir.appendingPathComponent("index.sqlite"))
    }

    override func tearDownWithError() throws {
        index = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func append(_ action: String, source: String?) async throws -> Int64 {
        try await index.journalAppend(
            batchID: "batch",
            sourcePath: "/src/\(UUID().uuidString).pdf",
            destinationPath: "/dst/x.pdf",
            categoryPath: "01_Fiscal",
            action: action,
            source: source
        )
    }

    func testStatsCountActionsAndSources() async throws {
        _ = try await append("move", source: "ai")
        _ = try await append("move", source: "ai")
        _ = try await append("move", source: "rules")
        _ = try await append("quarantine", source: nil)
        _ = try await append("simulate", source: "ai")
        let toUndo = try await append("move", source: "knowledge")
        try await index.journalMarkUndone(id: toUndo)

        let stats = try await index.journalStats(since: Date().addingTimeInterval(-3600))
        XCTAssertEqual(stats.archived, 4)
        XCTAssertEqual(stats.quarantined, 1)
        XCTAssertEqual(stats.simulated, 1)
        XCTAssertEqual(stats.undone, 1)
        XCTAssertEqual(stats.bySource["ai"], 2, "los simulate no cuentan en el desglose de fuentes")
        XCTAssertEqual(stats.bySource["rules"], 1)
        XCTAssertEqual(stats.bySource["knowledge"], 1)
        XCTAssertEqual(stats.bySource["(sin dato)"], 1, "los registros sin fuente se agrupan aparte")
        XCTAssertEqual(stats.days.count, 1, "todo cae en el día de hoy")
        XCTAssertEqual(stats.days.first?.archived, 4)
        XCTAssertEqual(stats.days.first?.quarantined, 1)
    }

    func testStatsRangeExcludesFuture() async throws {
        _ = try await append("move", source: "ai")
        let stats = try await index.journalStats(since: Date().addingTimeInterval(3600))
        XCTAssertEqual(stats.archived, 0)
        XCTAssertTrue(stats.days.isEmpty)
    }

    func testJournalEntryCarriesSource() async throws {
        let id = try await append("move", source: "manual")
        let entry = try await index.journalEntry(id: id)
        XCTAssertEqual(entry?.source, "manual")
        let recent = try await index.journalRecent(limit: 1)
        XCTAssertEqual(recent.first?.source, "manual")
    }

    func testJournalWithoutSourceReadsBackAsNil() async throws {
        let id = try await append("move", source: nil)
        let entry = try await index.journalEntry(id: id)
        XCTAssertNil(entry?.source)
    }

    /// Migración real: una base v4 (sin columna `source`) se abre, migra a v5 y conserva datos.
    func testReopenMigratesMissingSourceColumn() async throws {
        let dbURL = tempDir.appendingPathComponent("migrate.sqlite")
        let first = SearchIndex(databaseURL: dbURL)
        _ = try await first.journalAppend(
            batchID: "b",
            sourcePath: "/a.pdf",
            destinationPath: "/b.pdf",
            categoryPath: "c",
            action: "move",
            source: "ai"
        )

        // Simula la base anterior a N7: se quita la columna y se baja la versión a 4.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [dbURL.path, "ALTER TABLE ops_journal DROP COLUMN source; PRAGMA user_version = 4;"]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "sqlite3 debe poder quitar la columna (simulación v4)")

        // Reabrir: la migración v5 re-añade la columna y nada se pierde.
        let reopened = SearchIndex(databaseURL: dbURL)
        let stats = try await reopened.journalStats(since: Date().addingTimeInterval(-3600))
        XCTAssertEqual(stats.archived, 1, "el registro previo a la migración sigue contando")
        let recent = try await reopened.journalRecent(limit: 1)
        XCTAssertNil(recent.first?.source, "los registros antiguos quedan sin fuente")
    }
}
