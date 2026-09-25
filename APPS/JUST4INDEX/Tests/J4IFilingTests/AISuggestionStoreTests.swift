import XCTest
import Foundation
import J4ICore
@testable import J4IFiling

/// Caché persistente de sugerencias de la IA (petición del usuario 2026-09-24: «que haya lugar
/// para guardar las sugerencias… si no hay que gastar tokens de nuevo»).
final class AISuggestionStoreTests: XCTestCase {
    private func temporaryStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("j4i-ai-store-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("ai-suggestions.json")
    }

    private func suggestion(
        path: String = "/origen/foto.jpg",
        category: String = "13_Multimedia/Fotos"
    ) -> FilingCoordinator.Suggestion {
        FilingCoordinator.Suggestion(
            sourcePath: path,
            name: (path as NSString).lastPathComponent,
            categoryPath: category,
            confidence: 0.8,
            source: .ai,
            reason: "propuesta de prueba",
            isQuarantine: false
        )
    }

    func testStoresAndRetrievesSuggestionForMatchingFingerprint() {
        let url = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = AISuggestionStore(fileURL: url)
        let modified = Date(timeIntervalSince1970: 1_700_000_000)
        store.store(suggestion(), forPath: "/origen/foto.jpg", sizeBytes: 1234, modifiedAt: modified)

        let hit = store.suggestion(forPath: "/origen/foto.jpg", sizeBytes: 1234, modifiedAt: modified)
        XCTAssertEqual(hit?.categoryPath, "13_Multimedia/Fotos")
        XCTAssertEqual(hit?.confidence, 0.8)
        XCTAssertEqual(hit?.source, .ai)
        XCTAssertFalse(hit?.isQuarantine ?? true)
    }

    func testInvalidatesWhenFileChangedOrSkillVersionDiffers() {
        let url = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = AISuggestionStore(fileURL: url)
        let modified = Date(timeIntervalSince1970: 1_700_000_000)
        store.store(suggestion(), forPath: "/origen/foto.jpg", sizeBytes: 1234, modifiedAt: modified)

        // Tamaño distinto → huella obsoleta (el archivo cambió).
        XCTAssertNil(store.suggestion(forPath: "/origen/foto.jpg", sizeBytes: 9999, modifiedAt: modified))
        // Fecha distinta → huella obsoleta.
        XCTAssertNil(store.suggestion(forPath: "/origen/foto.jpg", sizeBytes: 1234, modifiedAt: Date(timeIntervalSince1970: 1_700_000_100)))
        // Skill distinta → obsoleta (al subir de versión se vuelve a preguntar).
        XCTAssertNil(store.entry(forPath: "/origen/foto.jpg", sizeBytes: 1234, modifiedAt: modified, skillVersion: FilingSkill.version + 1))
    }

    func testPersistsAcrossInstancesAndRemoves() {
        let url = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let modified = Date(timeIntervalSince1970: 1_700_000_000)
        do {
            let store = AISuggestionStore(fileURL: url)
            store.store(suggestion(), forPath: "/origen/foto.jpg", sizeBytes: 10, modifiedAt: modified)
            XCTAssertEqual(store.count, 1)
        }
        // Nueva instancia (simula cerrar y reabrir): la propuesta sigue ahí, sin llamar a la IA.
        let reopened = AISuggestionStore(fileURL: url)
        XCTAssertEqual(reopened.count, 1)
        XCTAssertNotNil(reopened.suggestion(forPath: "/origen/foto.jpg", sizeBytes: 10, modifiedAt: modified))

        reopened.remove(forPath: "/origen/foto.jpg")
        XCTAssertNil(reopened.suggestion(forPath: "/origen/foto.jpg", sizeBytes: 10, modifiedAt: modified))
        XCTAssertEqual(AISuggestionStore(fileURL: url).count, 0)
    }

    func testStoresFolderSplitStrategy() {
        let url = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = AISuggestionStore(fileURL: url)
        let modified = Date(timeIntervalSince1970: 1_700_000_000)
        let split = FilingCoordinator.Suggestion(
            sourcePath: "/origen/Documents",
            name: "Documents",
            categoryPath: "",
            confidence: 0.7,
            source: .ai,
            reason: "cajón heterogéneo",
            isQuarantine: false,
            folderStrategy: .split
        )
        store.store(split, forPath: "/origen/Documents", sizeBytes: 0, modifiedAt: modified)
        let hit = store.suggestion(forPath: "/origen/Documents", sizeBytes: 0, modifiedAt: modified)
        XCTAssertEqual(hit?.folderStrategy, .split, "la estrategia (desglosar) debe sobrevivir a la caché")
    }
}
