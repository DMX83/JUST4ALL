import XCTest
import J4ICore
@testable import J4IFiling

/// F12.0 — Base de conocimiento local: promoción conservadora, desacuerdos, corrección del
/// usuario (manda al momento), persistencia y extracción de características.
final class LocalKnowledgeStoreTests: XCTestCase {
    private func temporaryStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("j4i-knowledge-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("knowledge.json")
    }

    func testPromotionNeedsThreeConsistentObservations() {
        let url = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = LocalKnowledgeStore(fileURL: url)

        XCTAssertNil(store.promotedRule(kind: .fileExtension, value: "rsc"))
        XCTAssertFalse(store.record(kind: .fileExtension, value: "rsc", categoryPath: "12_Software/Redes", confidence: 0.9))
        XCTAssertFalse(store.record(kind: .fileExtension, value: "rsc", categoryPath: "12_Software/Redes", confidence: 0.8))
        XCTAssertTrue(store.record(kind: .fileExtension, value: "rsc", categoryPath: "12_Software/Redes", confidence: 0.85), "la tercera observación promueve")

        let rule = store.promotedRule(kind: .fileExtension, value: "rsc")
        XCTAssertEqual(rule?.categoryPath, "12_Software/Redes")
        XCTAssertGreaterThanOrEqual(rule?.confidence ?? 0, 0.7)
        XCTAssertEqual(rule?.observations, 3)
    }

    func testDisagreementPreventsPromotion() {
        let url = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = LocalKnowledgeStore(fileURL: url)

        store.record(kind: .fileExtension, value: "xyz", categoryPath: "A", confidence: 0.9)
        store.record(kind: .fileExtension, value: "xyz", categoryPath: "A", confidence: 0.9)
        store.record(kind: .fileExtension, value: "xyz", categoryPath: "B", confidence: 0.9)
        XCTAssertNil(store.promotedRule(kind: .fileExtension, value: "xyz"), "2/3 de acuerdo < 75 % → sin promoción")
    }

    func testUserCorrectionOverridePromotesImmediately() {
        let url = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = LocalKnowledgeStore(fileURL: url)

        store.record(kind: .fileExtension, value: "gguf", categoryPath: "12_Software/Desarrollo", confidence: 0.8)
        store.record(kind: .fileExtension, value: "gguf", categoryPath: "12_Software/Desarrollo", confidence: 0.8)
        store.record(kind: .fileExtension, value: "gguf", categoryPath: "12_Software/Desarrollo", confidence: 1.0, fromUser: true)

        let rule = store.promotedRule(kind: .fileExtension, value: "gguf")
        XCTAssertEqual(rule?.categoryPath, "12_Software/Desarrollo", "la corrección del usuario reescribe la regla")
    }

    func testPersistenceAndStats() {
        let url = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        do {
            let store = LocalKnowledgeStore(fileURL: url)
            for _ in 0..<3 {
                store.record(kind: .folderToken, value: "trading", categoryPath: "02_Banca/Inversiones", confidence: 0.85)
            }
            store.registerHit()
            XCTAssertEqual(store.stats().promotedCount, 1)
        }
        // Nueva instancia (reapertura): reglas y estadísticas persisten.
        let reopened = LocalKnowledgeStore(fileURL: url)
        XCTAssertEqual(reopened.promotedRule(kind: .folderToken, value: "trading")?.categoryPath, "02_Banca/Inversiones")
        let stats = reopened.stats()
        XCTAssertEqual(stats.promotedCount, 1)
        XCTAssertEqual(stats.appliedToday, 1)
        XCTAssertEqual(stats.appliedTotal, 1)
    }

    func testFolderTokenExtraction() {
        let tokens = KnowledgeFeatures.folderTokens(fromName: "Trading PRO 2024 – Edición Especial")
        XCTAssertTrue(tokens.contains("trading"))
        XCTAssertTrue(tokens.contains("especial"))
        XCTAssertFalse(tokens.contains("pro"), "palabras cortas/vacías fuera")
        XCTAssertFalse(tokens.contains("2024"), "números puros fuera")
    }

    func testFileExtensionExtraction() {
        XCTAssertEqual(KnowledgeFeatures.fileExtension(ofName: "Cake.RSC"), "rsc")
        XCTAssertNil(KnowledgeFeatures.fileExtension(ofName: "sin-extension"))
        XCTAssertNil(KnowledgeFeatures.fileExtension(ofName: ""))
    }
}
