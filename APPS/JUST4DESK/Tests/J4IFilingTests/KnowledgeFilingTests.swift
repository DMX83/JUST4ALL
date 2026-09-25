import XCTest
import J4ICore
import J4IIndex
@testable import J4IFiling

/// F12.0 — Integración del conocimiento local en el archivado: una regla promovida resuelve la
/// clasificación SIN llamar a la IA, y una corrección manual del usuario alimenta la base.
final class KnowledgeFilingTests: XCTestCase {
    private func temporaryStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("j4i-knowledge-filing-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("knowledge.json")
    }

    func testPromotedKnowledgeSkipsAIConsultation() async throws {
        let storeURL = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: storeURL.deletingLastPathComponent()) }
        let store = LocalKnowledgeStore(fileURL: storeURL)
        for _ in 0..<3 {
            store.record(kind: .fileExtension, value: "bin", categoryPath: "14_Comprimidos", confidence: 0.9)
        }
        XCTAssertNotNil(store.promotedRule(kind: .fileExtension, value: "bin"))

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("j4i-knowledge-run-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let rootURL = tempDir.appendingPathComponent("organizado", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let fileURL = tempDir.appendingPathComponent("datos.bin")
        try "binario".write(to: fileURL, atomically: true, encoding: .utf8)

        let index = SearchIndex(databaseURL: tempDir.appendingPathComponent("index.sqlite"))
        _ = try await index.addRoot(path: rootURL.path)

        // Sin IA disponible: sin la regla aprendida, «.bin» habría ido a «sin clasificar».
        let coordinator = FilingCoordinator(index: index, rootURL: rootURL, knowledge: store)
        let outcome = await coordinator.processItem(at: fileURL)

        XCTAssertEqual(outcome.action, "move")
        XCTAssertEqual(outcome.categoryPath, "14_Comprimidos")
        XCTAssertGreaterThanOrEqual(store.stats().appliedToday, 1, "la clasificación se resolvió con conocimiento local")
    }

    func testUserCorrectionFeedsKnowledgeImmediately() async throws {
        let storeURL = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: storeURL.deletingLastPathComponent()) }
        let store = LocalKnowledgeStore(fileURL: storeURL)

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("j4i-knowledge-correction-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let rootURL = tempDir.appendingPathComponent("organizado", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let fileURL = tempDir.appendingPathComponent("raro.bin")
        try "binario".write(to: fileURL, atomically: true, encoding: .utf8)

        let index = SearchIndex(databaseURL: tempDir.appendingPathComponent("index.sqlite"))
        _ = try await index.addRoot(path: rootURL.path)

        let coordinator = FilingCoordinator(index: index, rootURL: rootURL, knowledge: store)
        let outcome = await coordinator.reclassify(fileAt: fileURL, to: "14_Comprimidos")

        XCTAssertEqual(outcome.action, "move")
        let rule = store.promotedRule(kind: .fileExtension, value: "bin")
        XCTAssertEqual(rule?.categoryPath, "14_Comprimidos", "una corrección del usuario promueve la regla al momento")
    }
}
