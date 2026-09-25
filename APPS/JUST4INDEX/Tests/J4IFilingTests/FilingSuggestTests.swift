import XCTest
import J4ICore
import J4IIndex
@testable import J4IFiling

/// N2/N3: `proposeDestination` — la sugerencia usa el mismo criterio que el archivado pero
/// NUNCA mueve ni escribe journal (es solo una propuesta para «Por revisar»/Explorador).
final class FilingSuggestTests: XCTestCase {
    func testProposeDestinationForFolderUsesRulesAndDoesNotMove() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("j4i-suggest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let rootURL = tempDir.appendingPathComponent("organizado", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let sourceDir = tempDir.appendingPathComponent("entrada", isDirectory: true)
        let movieFolder = sourceDir.appendingPathComponent("Above Majestic Documental Completo", isDirectory: true)
        try FileManager.default.createDirectory(at: movieFolder, withIntermediateDirectories: true)
        try "video".write(to: movieFolder.appendingPathComponent("documental.mkv"), atomically: true, encoding: .utf8)

        let index = SearchIndex(databaseURL: tempDir.appendingPathComponent("index.sqlite"))
        _ = try await index.addRoot(path: rootURL.path)

        let coordinator = FilingCoordinator(index: index, rootURL: rootURL)
        let suggestion = await coordinator.proposeDestination(for: movieFolder)

        XCTAssertEqual(suggestion?.categoryPath, "13_Multimedia/Documentales")
        XCTAssertEqual(suggestion?.isQuarantine, false)
        // Es solo una propuesta: nada se movió ni quedó en el journal.
        XCTAssertTrue(FileManager.default.fileExists(atPath: movieFolder.path))
        let journal = try await index.journalRecent(limit: 10)
        XCTAssertTrue(journal.isEmpty)
    }

    func testProposeDestinationForFileUsesNameRules() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("j4i-suggest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let rootURL = tempDir.appendingPathComponent("organizado", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let sourceDir = tempDir.appendingPathComponent("entrada", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)

        let invoice = sourceDir.appendingPathComponent("Factura-Luz-Marzo.txt")
        try "factura de luz marzo".write(to: invoice, atomically: true, encoding: .utf8)

        let index = SearchIndex(databaseURL: tempDir.appendingPathComponent("index.sqlite"))
        _ = try await index.addRoot(path: rootURL.path)

        let coordinator = FilingCoordinator(index: index, rootURL: rootURL)
        let suggestion = await coordinator.proposeDestination(for: invoice)

        XCTAssertEqual(suggestion?.categoryPath, "01_Fiscal/Facturas")
        XCTAssertEqual(suggestion?.source, .rules)
        XCTAssertTrue(FileManager.default.fileExists(atPath: invoice.path))
    }

    func testProposeDestinationFallsBackToQuarantineWithoutSignal() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("j4i-suggest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let rootURL = tempDir.appendingPathComponent("organizado", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let sourceDir = tempDir.appendingPathComponent("entrada", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)

        let notes = sourceDir.appendingPathComponent("notas.txt")
        try "apuntes varios sin contexto claro".write(to: notes, atomically: true, encoding: .utf8)

        let index = SearchIndex(databaseURL: tempDir.appendingPathComponent("index.sqlite"))
        _ = try await index.addRoot(path: rootURL.path)

        let coordinator = FilingCoordinator(index: index, rootURL: rootURL)
        let suggestion = await coordinator.proposeDestination(for: notes)

        XCTAssertEqual(suggestion?.categoryPath, "99_SinClasificar")
        XCTAssertEqual(suggestion?.isQuarantine, true)
    }
}
