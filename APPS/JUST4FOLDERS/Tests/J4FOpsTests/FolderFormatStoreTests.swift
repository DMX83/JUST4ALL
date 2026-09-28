import XCTest
@testable import J4FOps

final class FolderFormatStoreTests: XCTestCase {
    private var url: URL!

    override func setUpWithError() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("j4f-formats-\(UUID().uuidString).json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: url)
    }

    func testSetGetRemoveRoundTrip() throws {
        let store = FolderFormatStore(url: url, capacity: 10)
        let format = FolderFormat(flatView: true, sortColumn: "size", ascending: false, includeHidden: true)
        store.set(format, for: "/tmp/demo")

        XCTAssertEqual(store.format(for: "/tmp/demo"), format)
        XCTAssertNil(store.format(for: "/tmp/otro"))

        store.remove(for: "/tmp/demo")
        XCTAssertNil(store.format(for: "/tmp/demo"))
    }

    func testColumnWidthsRoundTrip() throws {
        let store = FolderFormatStore(url: url, capacity: 10)
        store.set(FolderFormat(columnWidths: ["name": 220, "size": 80]), for: "/tmp/columnas")

        // v2.1.1 — los anchos manuales sobreviven al guardado y al JSON.
        let reopened = FolderFormatStore(url: url, capacity: 10)
        XCTAssertEqual(reopened.format(for: "/tmp/columnas")?.columnWidths?["name"], 220)
        XCTAssertEqual(reopened.format(for: "/tmp/columnas")?.columnWidths?["size"], 80)
        XCTAssertNil(FolderFormat().columnWidths)
    }

    func testPersistsAcrossInstances() throws {
        let store = FolderFormatStore(url: url, capacity: 10)
        store.set(.init(flatView: true, sortColumn: "modified", ascending: false), for: "/tmp/persistente")

        let reopened = FolderFormatStore(url: url, capacity: 10)
        XCTAssertEqual(reopened.format(for: "/tmp/persistente")?.sortColumn, "modified")
        XCTAssertEqual(reopened.format(for: "/tmp/persistente")?.flatView, true)
    }

    func testLRUEvictsOldestBeyondCapacity() throws {
        let store = FolderFormatStore(url: url, capacity: 3)
        for index in 0..<4 {
            store.set(.init(flatView: index % 2 == 0), for: "/tmp/carpeta-\(index)")
        }
        XCTAssertNil(store.format(for: "/tmp/carpeta-0"), "la más antigua se descarta")
        XCTAssertNotNil(store.format(for: "/tmp/carpeta-3"))

        // Re-escribir la 1 la rejuvenece: al añadir otra, cae la 2 (no la 1).
        store.set(.init(flatView: true), for: "/tmp/carpeta-1")
        store.set(.init(flatView: false), for: "/tmp/carpeta-4")
        XCTAssertNotNil(store.format(for: "/tmp/carpeta-1"))
        XCTAssertNil(store.format(for: "/tmp/carpeta-2"))
    }
}
