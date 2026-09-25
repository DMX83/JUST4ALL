import XCTest
import J4ICore
@testable import J4IFiling
import J4IIndex

/// G6 — informe semanal: cuenta lo del periodo (move/cold/quarantine), suma datos ordenados,
/// deshechos aparte, top de categorías, reglas promovidas y ahorro estimado; genera Markdown.
final class WeeklyReportTests: XCTestCase {
    private var tempDir: URL!
    private var root: URL!
    private var index: SearchIndex!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("j4i-report-\(UUID().uuidString)", isDirectory: true)
        root = tempDir.appendingPathComponent("archivo", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        index = SearchIndex(databaseURL: tempDir.appendingPathComponent("index.sqlite"))
    }

    override func tearDownWithError() throws {
        index = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    @discardableResult
    private func makeFile(relativePath: String, bytes: Int) throws -> URL {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: bytes).write(to: url)
        return url
    }

    func testBuildCountsBytesAndMarkdown() async throws {
        let movedFile = try makeFile(relativePath: "01_Fiscal/factura.pdf", bytes: 1000)
        let coldFile = try makeFile(relativePath: "90_Archivo/13_Multimedia/peli.mp4", bytes: 2000)

        _ = try await index.journalAppend(batchID: "b1", sourcePath: "/src/a", destinationPath: movedFile.path, categoryPath: "01_Fiscal", action: "move")
        _ = try await index.journalAppend(batchID: "b2", sourcePath: "/src/b", destinationPath: coldFile.path, categoryPath: "90_Archivo/13_Multimedia", action: "cold")
        _ = try await index.journalAppend(batchID: "b3", sourcePath: "/src/c", destinationPath: "\(root.path)/99_SinClasificar/duda.pdf", categoryPath: "99_SinClasificar", action: "quarantine")
        _ = try await index.journalAppend(batchID: "b4", sourcePath: "/src/d", destinationPath: movedFile.path, categoryPath: "01_Fiscal", action: "move")
        let last = try await index.journalRecent(limit: 1)
        try await index.journalMarkUndone(id: try XCTUnwrap(last.first).id)

        let knowledge = LocalKnowledgeStore(fileURL: tempDir.appendingPathComponent("knowledge.json"))
        for _ in 0..<3 {
            knowledge.record(kind: .fileExtension, value: "rsc", categoryPath: "12_Software/Redes", confidence: 0.9)
        }
        knowledge.registerHit()
        knowledge.registerHit()

        let report = await WeeklyReport.build(
            index: index,
            rootURL: root,
            knowledge: knowledge,
            aiCallsTotal: 10,
            aiTokensTotal: 1000
        )

        XCTAssertEqual(report.filedCount, 1)
        XCTAssertEqual(report.coldCount, 1)
        XCTAssertEqual(report.quarantinedCount, 1)
        XCTAssertEqual(report.undoneCount, 1, "el deshecho no cuenta como archivado")
        XCTAssertEqual(report.movedBytes, 3000, "1000 (move) + 2000 (cold)")
        XCTAssertEqual(report.topCategories.map(\.path), ["01_Fiscal", "90_Archivo/13_Multimedia"])
        XCTAssertEqual(report.promotedRulesThisWeek, 1)
        XCTAssertEqual(report.knowledgeAppliedTotal, 2)
        XCTAssertEqual(report.estimatedTokensSaved, 200, "2 usos × 100 tokens de media")
        XCTAssertEqual(report.pendingReview, 0)

        let markdown = report.markdown
        XCTAssertTrue(markdown.contains("# Informe semanal — JUST4DESK"))
        XCTAssertTrue(markdown.contains("Archivados: **1**"))
        XCTAssertTrue(markdown.contains("Reglas promovidas esta semana: **1**"))
    }
}
