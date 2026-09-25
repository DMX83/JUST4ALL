import XCTest
import J4ICore
import J4IIndex
@testable import J4IFiling

final class FilingReclassifyTests: XCTestCase {
    func testReclassifyMovesFromQuarantineWithJournalAndUndo() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("j4i-review-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let rootURL = tempDir.appendingPathComponent("organizado", isDirectory: true)
        let quarantineURL = rootURL.appendingPathComponent(DefaultTaxonomy.quarantineRelativePath, isDirectory: true)
        try FileManager.default.createDirectory(at: quarantineURL, withIntermediateDirectories: true)

        let fileName = "AnyDesk-Setup.exe"
        let sourceURL = quarantineURL.appendingPathComponent(fileName)
        try "instalador de prueba".write(to: sourceURL, atomically: true, encoding: .utf8)

        let index = SearchIndex(databaseURL: tempDir.appendingPathComponent("index.sqlite"))
        let root = try await index.addRoot(path: rootURL.path)
        _ = try await index.upsertEntries(rootID: root.id, [
            IndexEntryWrite(url: sourceURL, isDirectory: false, sizeBytes: 18, modifiedAt: Date())
        ])
        if let entryID = try? await index.entryID(path: sourceURL.path) {
            try? await index.setDocumentText(entryID: entryID, text: "anydesk escritorio remoto")
        }

        // Sugerencia de las reglas locales: extensión .exe → instaladores.
        XCTAssertEqual(RulesFilingClassifier.suggestDestination(fileName: fileName)?.categoryPath, "12_Software/Instaladores")

        // Aislamiento (F12.0): las correcciones de los tests no deben tocar el conocimiento real.
        let knowledge = LocalKnowledgeStore(fileURL: tempDir.appendingPathComponent("knowledge.json"))
        let coordinator = FilingCoordinator(index: index, rootURL: rootURL, knowledge: knowledge)
        let outcome = await coordinator.reclassify(fileAt: sourceURL, to: "12_Software/Instaladores")

        XCTAssertEqual(outcome.action, "move")
        XCTAssertEqual(outcome.categoryPath, "12_Software/Instaladores")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outcome.destinationPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))

        // El texto ya extraído viaja al nuevo registro (la búsqueda por contenido no se pierde).
        let newEntryID = try? await index.entryID(path: outcome.destinationPath)
        XCTAssertNotNil(newEntryID, "la nueva ubicación debe estar en el índice")
        if let newEntryID {
            let text = try await index.documentText(entryID: newEntryID)
            XCTAssertEqual(text, "anydesk escritorio remoto")
        }

        // Journal + undo: la acción manual es reversible desde Actividad.
        let journal = try await index.journalRecent(limit: 10)
        XCTAssertEqual(journal.count, 1)
        XCTAssertEqual(journal[0].action, "move")
        XCTAssertEqual(journal[0].destinationPath, outcome.destinationPath)
        XCTAssertTrue(journal[0].isUndoable)

        let undone = await coordinator.undo(entry: journal[0])
        XCTAssertTrue(undone)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outcome.destinationPath))
    }

    func testReclassifyResolvesNameCollisionWithoutOverwriting() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("j4i-review-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let rootURL = tempDir.appendingPathComponent("organizado", isDirectory: true)
        let quarantineURL = rootURL.appendingPathComponent(DefaultTaxonomy.quarantineRelativePath, isDirectory: true)
        let categoryURL = rootURL.appendingPathComponent("12_Software/Instaladores", isDirectory: true)
        try FileManager.default.createDirectory(at: quarantineURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: categoryURL, withIntermediateDirectories: true)

        // Ya existe un fichero con el mismo nombre en el destino: no se debe sobrescribir.
        let existingURL = categoryURL.appendingPathComponent("AnyDesk-Setup.exe")
        try "existente".write(to: existingURL, atomically: true, encoding: .utf8)

        let sourceURL = quarantineURL.appendingPathComponent("AnyDesk-Setup.exe")
        try "nuevo".write(to: sourceURL, atomically: true, encoding: .utf8)

        let index = SearchIndex(databaseURL: tempDir.appendingPathComponent("index.sqlite"))
        _ = try await index.addRoot(path: rootURL.path)

        // Aislamiento (F12.0): las correcciones de los tests no deben tocar el conocimiento real.
        let knowledge = LocalKnowledgeStore(fileURL: tempDir.appendingPathComponent("knowledge.json"))
        let coordinator = FilingCoordinator(index: index, rootURL: rootURL, knowledge: knowledge)
        let outcome = await coordinator.reclassify(fileAt: sourceURL, to: "12_Software/Instaladores")

        XCTAssertEqual(outcome.action, "move")
        XCTAssertEqual((outcome.destinationPath as NSString).lastPathComponent, "AnyDesk-Setup-1.exe")
        XCTAssertTrue(FileManager.default.fileExists(atPath: existingURL.path))
        XCTAssertEqual(try String(contentsOf: existingURL, encoding: .utf8), "existente")
        XCTAssertEqual(try String(contentsOf: URL(fileURLWithPath: outcome.destinationPath), encoding: .utf8), "nuevo")
    }
}
