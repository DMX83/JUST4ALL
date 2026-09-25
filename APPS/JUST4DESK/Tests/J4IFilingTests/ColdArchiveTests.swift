import XCTest
import J4ICore
@testable import J4IFiling
import J4IIndex

/// G6 — archivo en frío: `90_Archivo/…` conservando la ruta relativa, con journal y deshacer.
final class ColdArchiveTests: XCTestCase {
    private var tempDir: URL!
    private var root: URL!
    private var index: SearchIndex!
    private var coordinator: FilingCoordinator!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("j4i-cold-\(UUID().uuidString)", isDirectory: true)
        root = tempDir.appendingPathComponent("archivo", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        index = SearchIndex(databaseURL: tempDir.appendingPathComponent("index.sqlite"))
        let knowledge = LocalKnowledgeStore(fileURL: tempDir.appendingPathComponent("knowledge.json"))
        coordinator = FilingCoordinator(index: index, rootURL: root, knowledge: knowledge)
    }

    override func tearDownWithError() throws {
        coordinator = nil
        index = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    @discardableResult
    private func makeFile(relativePath: String, bytes: Int = 5000) throws -> URL {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x42, count: bytes).write(to: url)
        return url
    }

    func testArchiveColdMovesPreservingRelativePathAndJournals() async throws {
        let original = try makeFile(relativePath: "13_Multimedia/Videos/peli.mp4")
        let rootEntry = try await index.addRoot(path: root.path)
        try await index.upsertEntries(rootID: rootEntry.id, [
            IndexEntryWrite(url: original, isDirectory: false, sizeBytes: 5000, modifiedAt: Date())
        ])

        let outcome = await coordinator.archiveCold(at: original)

        XCTAssertEqual(outcome.action, "cold")
        XCTAssertEqual(outcome.categoryPath, "90_Archivo/13_Multimedia/Videos")
        let destination = root.appendingPathComponent("90_Archivo/13_Multimedia/Videos/peli.mp4")
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path), "queda en 90_Archivo con su ruta")
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path), "el original ya no está")

        let journal = try await index.journalRecent(limit: 5)
        XCTAssertEqual(journal.first?.action, "cold")
        XCTAssertEqual(journal.first?.isUndoable, true, "el archivo en frío se puede deshacer")

        let oldEntryID = try await index.entryID(path: original.path)
        XCTAssertNil(oldEntryID, "la entrada antigua del índice se limpia")
        let newEntryID = try await index.entryID(path: destination.path)
        XCTAssertNotNil(newEntryID, "el nuevo sitio queda indexado")
    }

    func testArchiveColdUndoRestoresOriginalPlace() async throws {
        let original = try makeFile(relativePath: "12_Software/Instaladores/viejo.pkg")
        _ = await coordinator.archiveCold(at: original)
        let journal = try await index.journalRecent(limit: 5)
        let entry = try XCTUnwrap(journal.first)

        let undone = await coordinator.undo(entry: entry)

        XCTAssertTrue(undone)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path), "vuelve a su sitio original")
        let destination = root.appendingPathComponent("90_Archivo/12_Software/Instaladores/viejo.pkg")
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testArchiveColdRejectsElementsOutsideRoot() async throws {
        let outside = tempDir.appendingPathComponent("lejos.txt")
        try Data("hola".utf8).write(to: outside)

        let outcome = await coordinator.archiveCold(at: outside)

        XCTAssertEqual(outcome.action, "error")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }
}
