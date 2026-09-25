import XCTest
import J4ICore
import J4IIndex
@testable import J4IFiling

final class FilingCoordinatorTests: XCTestCase {
    private var tempDir: URL!
    private var index: SearchIndex!
    private var rootURL: URL!
    private var sourceURL: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("j4i-filing-\(UUID().uuidString)", isDirectory: true)
        rootURL = tempDir.appendingPathComponent("organizado", isDirectory: true)
        sourceURL = tempDir.appendingPathComponent("entrada", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        index = SearchIndex(databaseURL: tempDir.appendingPathComponent("index.sqlite"))
    }

    override func tearDownWithError() throws {
        index = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeCoordinator(simulation: Bool = false) -> FilingCoordinator {
        // Conocimiento local aislado (F12.0): los tests no deben leer ni escribir el almacén real.
        let knowledge = LocalKnowledgeStore(fileURL: tempDir.appendingPathComponent("knowledge.json"))
        return FilingCoordinator(index: index, rootURL: rootURL, simulationMode: simulation, advisor: nil, knowledge: knowledge)
    }

    func testProcessesInvoiceIntoFiscalFacturas() async throws {
        let fileURL = sourceURL.appendingPathComponent("Factura-Luz-Marzo.txt")
        try "Factura de electricidad. Importe 85,00 €".write(to: fileURL, atomically: true, encoding: .utf8)

        let coordinator = makeCoordinator()
        let outcome = await coordinator.processFile(at: fileURL)

        XCTAssertEqual(outcome.action, "move")
        XCTAssertEqual(outcome.categoryPath, "01_Fiscal/Facturas")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outcome.destinationPath))

        let entries = try await index.journalRecent(limit: 10)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.action, "move")
        XCTAssertTrue(entries.first?.isUndoable == true)
    }

    func testUndoRestoresOriginalFile() async throws {
        let fileURL = sourceURL.appendingPathComponent("Factura-Undo.txt")
        try "Factura de prueba. Importe 10,00 €".write(to: fileURL, atomically: true, encoding: .utf8)

        let coordinator = makeCoordinator()
        let outcome = await coordinator.processFile(at: fileURL)
        XCTAssertEqual(outcome.action, "move")

        let entries = try await index.journalRecent(limit: 10)
        let entry = try XCTUnwrap(entries.first)
        let undone = await coordinator.undo(entry: entry)
        XCTAssertTrue(undone)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outcome.destinationPath))

        let updated = try await index.journalEntry(id: entry.id)
        XCTAssertEqual(updated?.state, "undone")
    }

    func testSimulationModeDoesNotMove() async throws {
        let fileURL = sourceURL.appendingPathComponent("Factura-Simulada.txt")
        try "Factura simulada. Importe 20,00 €".write(to: fileURL, atomically: true, encoding: .utf8)

        let coordinator = makeCoordinator(simulation: true)
        let outcome = await coordinator.processFile(at: fileURL)

        XCTAssertEqual(outcome.action, "simulate")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path), "en simulación el fichero no se mueve")
        XCTAssertFalse(FileManager.default.fileExists(atPath: outcome.destinationPath))

        let entries = try await index.journalRecent(limit: 10)
        XCTAssertEqual(entries.first?.action, "simulate")
    }

    func testDuplicateIsSkippedAndLeftInSource() async throws {
        let first = sourceURL.appendingPathComponent("unico-a.txt")
        try "contenido único de prueba 12345".write(to: first, atomically: true, encoding: .utf8)

        let coordinator = makeCoordinator()
        _ = await coordinator.processFile(at: first)

        let second = sourceURL.appendingPathComponent("unico-b.txt")
        try "contenido único de prueba 12345".write(to: second, atomically: true, encoding: .utf8)
        let outcome = await coordinator.processFile(at: second)

        XCTAssertEqual(outcome.action, "skipped-duplicate")
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path), "el duplicado se deja en origen")
    }

    func testAmbiguousDocumentGoesToQuarantine() async throws {
        let fileURL = sourceURL.appendingPathComponent("documento-generico-xyz.txt")
        try "nada clasificable por aquí".write(to: fileURL, atomically: true, encoding: .utf8)

        let coordinator = makeCoordinator()
        let outcome = await coordinator.processFile(at: fileURL)

        XCTAssertEqual(outcome.action, "quarantine")
        XCTAssertEqual(outcome.categoryPath, "99_SinClasificar")
        XCTAssertTrue(outcome.destinationPath.contains("99_SinClasificar"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outcome.destinationPath))
    }
}
