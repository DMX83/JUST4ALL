import XCTest
@testable import J4FOps

final class FolderOrdererTests: XCTestCase {
    private var sourceDir: URL!
    private var destDir: URL!

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("j4f-order-\(UUID().uuidString)", isDirectory: true)
        sourceDir = base.appendingPathComponent("origen", isDirectory: true)
        destDir = base.appendingPathComponent("destino", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: sourceDir.deletingLastPathComponent())
    }

    private func makeFile(_ name: String, in directory: URL? = nil) throws -> URL {
        let url = (directory ?? sourceDir).appendingPathComponent(name)
        try "x".data(using: .utf8)?.write(to: url)
        return url
    }

    func testPlanRoutesKnownKeywordToTaxonomyCategory() throws {
        let file = try makeFile("nomina-marzo.pdf")
        let plan = FolderOrderer.plan(files: [file])
        XCTAssertEqual(plan.first?.destinationRelativePath, "01_Fiscal/Nominas")
        XCTAssertEqual(plan.first?.finalName, "nomina-marzo.pdf")
        XCTAssertFalse(plan.first?.isQuarantine ?? true)
        XCTAssertEqual(plan.first?.reason.contains("regla local") ?? false, true, "motivo trazable: \(plan.first?.reason ?? "-")")
    }

    func testUnknownGoesToQuarantineOrSkips() throws {
        let file = try makeFile("asdf.qwerty")
        let quarantine = FolderOrderer.plan(files: [file])
        XCTAssertEqual(quarantine.first?.destinationRelativePath, "99_SinClasificar")
        XCTAssertTrue(quarantine.first?.isQuarantine ?? false)

        let skip = FolderOrderer.plan(files: [file], options: .init(categorizeUnknown: false))
        if case .skip = skip.first?.disposition {} else {
            XCTFail("con categorizeUnknown=false debería quedarse en su sitio")
        }
    }

    func testApplyMovesCreatesCategoriesAndJournals() throws {
        let nomina = try makeFile("nomina-marzo.pdf")
        let plan = FolderOrderer.plan(files: [nomina])
        let result = FolderOrderer.apply(plan, destinationRoot: destDir)

        XCTAssertEqual(result.moved, 1)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertEqual(result.journal.count, 1)

        let destination = destDir
            .appendingPathComponent("01_Fiscal/Nominas/nomina-marzo.pdf")
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path), "crea la categoría y mueve")
        XCTAssertFalse(FileManager.default.fileExists(atPath: nomina.path), "el original ya no está")

        // Deshacer lo devuelve a su sitio.
        let undone = FolderOrderer.undo(result.journal)
        XCTAssertEqual(undone.restored, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: nomina.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testApplyAvoidsNameCollisionsWithSuffix() throws {
        // Dos nombres que sanean igual dentro de la misma categoría (99_SinClasificar).
        let a = try makeFile("nota rara.qwerty")
        let b = try makeFile("nota-rara.qwerty")
        let plan = FolderOrderer.plan(files: [a, b])
        let result = FolderOrderer.apply(plan, destinationRoot: destDir)

        XCTAssertEqual(result.moved, 2)
        let folder = destDir.appendingPathComponent("99_SinClasificar")
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        XCTAssertEqual(names, ["nota-rara 2.qwerty", "nota-rara.qwerty"], "el segundo recibe sufijo")
    }

    func testJournalStoreRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("j4f-journal-\(UUID().uuidString).json")
        defer { OrderingJournalStore.clear(at: url) }

        let moves = [FolderOrderer.Move(source: "/a/uno.pdf", destination: "/b/01_Fiscal/uno.pdf")]
        OrderingJournalStore.save(moves, to: url)
        XCTAssertEqual(OrderingJournalStore.load(from: url), moves)

        OrderingJournalStore.clear(at: url)
        XCTAssertTrue(OrderingJournalStore.load(from: url).isEmpty)
    }
}
