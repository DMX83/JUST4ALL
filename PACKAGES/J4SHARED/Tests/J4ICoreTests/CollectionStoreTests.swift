import XCTest
@testable import J4ICore

/// G5 — colecciones guardadas: alta saneada, persistencia, edición y borrado (sin tocar ficheros).
final class CollectionStoreTests: XCTestCase {
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("j4i-collections-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("collections.json")
    }

    func testAddListAndPersistAcrossInstances() {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        do {
            let store = CollectionStore(fileURL: url)
            XCTAssertTrue(store.all().isEmpty)

            let added = store.add(name: "  Trading ", query: " trading ")
            XCTAssertEqual(added?.name, "Trading", "sanea espacios alrededor")
            XCTAssertEqual(added?.query, "trading")
            XCTAssertEqual(store.all().count, 1)
        }
        let reopened = CollectionStore(fileURL: url)
        XCTAssertEqual(reopened.all().first?.name, "Trading")
        XCTAssertEqual(reopened.all().first?.query, "trading")
    }

    func testRejectsEmptyNameOrQuery() {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = CollectionStore(fileURL: url)
        XCTAssertNil(store.add(name: "   ", query: "trading"))
        XCTAssertNil(store.add(name: "Trading", query: "  "))
        XCTAssertTrue(store.all().isEmpty)
    }

    func testUpdateAndRemove() {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = CollectionStore(fileURL: url)
        guard let collection = store.add(name: "Fiscal 2026", query: "fiscal") else {
            return XCTFail("no se pudo crear la colección")
        }

        XCTAssertTrue(store.update(id: collection.id, name: "Fiscal", query: "factura"))
        XCTAssertEqual(store.all().first?.name, "Fiscal")
        XCTAssertEqual(store.all().first?.query, "factura")
        XCTAssertFalse(store.update(id: "no-existe", name: "X", query: "y"))

        XCTAssertTrue(store.remove(id: collection.id))
        XCTAssertTrue(store.all().isEmpty)
        XCTAssertFalse(store.remove(id: collection.id))
    }

    func testCapsLengths() {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = CollectionStore(fileURL: url)
        let added = store.add(
            name: String(repeating: "a", count: 200),
            query: String(repeating: "b", count: 500)
        )
        XCTAssertEqual(added?.name.count, CollectionStore.maxNameLength)
        XCTAssertEqual(added?.query.count, CollectionStore.maxQueryLength)
    }

    func testCorruptFileIsIgnored() {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data("no-json".utf8).write(to: url)

        let store = CollectionStore(fileURL: url)
        XCTAssertTrue(store.all().isEmpty, "un archivo ilegible se ignora sin romper")
    }
}
