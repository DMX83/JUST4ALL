import XCTest
@testable import J4IIndex

/// G6 — consulta del journal por rango temporal (informe semanal).
final class JournalRangeTests: XCTestCase {
    private var tempDir: URL!
    private var index: SearchIndex!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("j4i-journal-range-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        index = SearchIndex(databaseURL: tempDir.appendingPathComponent("index.sqlite"))
    }

    override func tearDownWithError() throws {
        index = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testJournalEntriesFilterByDateRange() async throws {
        _ = try await index.journalAppend(
            batchID: "r1",
            sourcePath: "/tmp/origen.pdf",
            destinationPath: "/tmp/destino.pdf",
            categoryPath: "01_Fiscal",
            action: "move"
        )
        let now = Date()

        let recent = try await index.journalEntries(
            since: now.addingTimeInterval(-3600),
            until: now.addingTimeInterval(60),
            limit: 10
        )
        XCTAssertEqual(recent.count, 1)
        XCTAssertEqual(recent.first?.action, "move")

        let future = try await index.journalEntries(
            since: now.addingTimeInterval(3600),
            until: now.addingTimeInterval(7200),
            limit: 10
        )
        XCTAssertTrue(future.isEmpty, "un rango posterior no devuelve nada")

        let past = try await index.journalEntries(
            since: now.addingTimeInterval(-7200),
            until: now.addingTimeInterval(-3600),
            limit: 10
        )
        XCTAssertTrue(past.isEmpty, "un rango anterior no devuelve nada")
    }
}
