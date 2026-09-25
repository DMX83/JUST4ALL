import XCTest
@testable import J4IFiling

/// G3 — gestión y portabilidad del conocimiento local: listar, editar, borrar, crear a mano y
/// exportar/importar (fusión por muestras; lo local no se pierde con importaciones más pobres).
final class KnowledgePortabilityTests: XCTestCase {
    private func temporaryStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("j4i-knowledge-portability-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("knowledge.json")
    }

    private func promote(
        _ store: LocalKnowledgeStore,
        kind: LocalKnowledgeStore.FeatureKind = .fileExtension,
        value: String,
        category: String,
        times: Int = 3
    ) {
        for _ in 0..<times {
            store.record(kind: kind, value: value, categoryPath: category, confidence: 0.9)
        }
    }

    func testRulesListingOrdersPromotedFirst() {
        let url = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = LocalKnowledgeStore(fileURL: url)

        promote(store, value: "rsc", category: "12_Software/Redes")
        store.record(kind: .folderToken, value: "trading", categoryPath: "02_Banca/Inversiones", confidence: 0.9)

        let rules = store.rules()
        XCTAssertEqual(rules.count, 2)
        XCTAssertTrue(rules[0].isPromoted)
        XCTAssertEqual(rules[0].displayValue, ".rsc")
        XCTAssertFalse(rules[1].isPromoted)
        XCTAssertEqual(rules[1].displayValue, "trading")
        XCTAssertEqual(rules[1].total, 1)
    }

    func testSetDestinationPromotesImmediately() {
        let url = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = LocalKnowledgeStore(fileURL: url)

        store.record(kind: .fileExtension, value: "xyz", categoryPath: "A", confidence: 0.9)
        store.setDestination("B", kind: .fileExtension, value: "xyz")

        XCTAssertEqual(store.promotedRule(kind: .fileExtension, value: "xyz")?.categoryPath, "B")
        XCTAssertEqual(store.rules().first?.categoryPath, "B")
    }

    func testRemoveRuleDeletesAndPersists() {
        let url = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        do {
            let store = LocalKnowledgeStore(fileURL: url)
            promote(store, value: "gguf", category: "12_Software/Desarrollo")
            XCTAssertTrue(store.removeRule(kind: .fileExtension, value: "GGUF"), "normaliza el valor")
        }
        let reopened = LocalKnowledgeStore(fileURL: url)
        XCTAssertNil(reopened.promotedRule(kind: .fileExtension, value: "gguf"))
        XCTAssertTrue(reopened.rules().isEmpty)
    }

    func testAddManualRuleIsUsableImmediately() {
        let url = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = LocalKnowledgeStore(fileURL: url)

        store.addManualRule(kind: .folderToken, value: "Trading", categoryPath: "02_Banca/Inversiones")
        let rule = store.promotedRule(kind: .folderToken, value: "trading")
        XCTAssertEqual(rule?.categoryPath, "02_Banca/Inversiones")
        XCTAssertGreaterThanOrEqual(rule?.confidence ?? 0, 0.9)
    }

    func testExportImportRoundTripMergesByObservations() {
        let urlA = temporaryStoreURL()
        let urlB = temporaryStoreURL()
        defer {
            try? FileManager.default.removeItem(at: urlA.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: urlB.deletingLastPathComponent())
        }
        let storeA = LocalKnowledgeStore(fileURL: urlA)
        promote(storeA, value: "rsc", category: "12_Software/Redes")
        storeA.record(kind: .fileExtension, value: "heic", categoryPath: "13_Multimedia/Fotos", confidence: 0.8)

        guard let data = storeA.exportData() else {
            return XCTFail("exportData devolvió nil")
        }
        let storeB = LocalKnowledgeStore(fileURL: urlB)
        let first = storeB.importData(data)
        XCTAssertEqual(first?.added, 2)
        XCTAssertEqual(storeB.promotedRule(kind: .fileExtension, value: "rsc")?.categoryPath, "12_Software/Redes")

        // Repetir la importación con los mismos datos no duplica ni pisa: todo «sin cambios».
        let second = storeB.importData(data)
        XCTAssertEqual(second?.added, 0)
        XCTAssertEqual(second?.kept, 2)
        XCTAssertEqual(second?.replaced, 0)
    }

    func testImportPrefersEntryWithMoreObservations() {
        let urlA = temporaryStoreURL()
        let urlB = temporaryStoreURL()
        defer {
            try? FileManager.default.removeItem(at: urlA.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: urlB.deletingLastPathComponent())
        }
        let storeA = LocalKnowledgeStore(fileURL: urlA)
        promote(storeA, value: "rsc", category: "12_Software/Redes", times: 6)

        let storeB = LocalKnowledgeStore(fileURL: urlB)
        promote(storeB, value: "rsc", category: "12_Software/Herramientas")

        guard let data = storeA.exportData() else {
            return XCTFail("exportData devolvió nil")
        }
        let report = storeB.importData(data)
        XCTAssertEqual(report?.replaced, 1)
        XCTAssertEqual(storeB.promotedRule(kind: .fileExtension, value: "rsc")?.categoryPath, "12_Software/Redes")
        XCTAssertEqual(storeB.rules().first?.positives, 6)
    }

    func testImportRejectsForeignFile() {
        let url = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = LocalKnowledgeStore(fileURL: url)
        XCTAssertNil(store.importData(Data("{\"hello\":1}".utf8)))
    }
}
