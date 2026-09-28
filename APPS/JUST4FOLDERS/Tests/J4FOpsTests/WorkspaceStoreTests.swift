import XCTest
@testable import J4FOps

final class WorkspaceStoreTests: XCTestCase {
    private var url: URL!

    override func setUpWithError() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("j4f-ws-\(UUID().uuidString).json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: url)
    }

    private func makeWorkspace(name: String, leftTab: String = "/tmp/a") -> Workspace {
        Workspace(
            name: name,
            left: PanelWorkspace(tabs: [leftTab, "/tmp/b"], activeIndex: 0),
            right: PanelWorkspace(tabs: ["/tmp/c"], activeIndex: 0),
            previewPaneVisible: true
        )
    }

    func testSaveLoadReplaceRemove() throws {
        let store = WorkspaceStore(url: url)
        store.save(makeWorkspace(name: "Trabajo"))
        store.save(makeWorkspace(name: "Fotos", leftTab: "/tmp/fotos"))

        XCTAssertEqual(store.all().map(\.name), ["Fotos", "Trabajo"])

        // Reemplazo por nombre.
        store.save(makeWorkspace(name: "Trabajo", leftTab: "/tmp/nuevo"))
        XCTAssertEqual(store.workspace(named: "Trabajo")?.left.tabs.first, "/tmp/nuevo")
        XCTAssertEqual(store.all().count, 2)

        XCTAssertTrue(store.remove(named: "Fotos"))
        XCTAssertFalse(store.remove(named: "Fotos"))
        XCTAssertEqual(store.all().map(\.name), ["Trabajo"])
    }

    func testPersistsAcrossInstances() throws {
        let store = WorkspaceStore(url: url)
        store.save(makeWorkspace(name: "Persistente"))

        let reopened = WorkspaceStore(url: url)
        let loaded = reopened.workspace(named: "Persistente")
        XCTAssertEqual(loaded?.left.tabs, ["/tmp/a", "/tmp/b"])
        XCTAssertEqual(loaded?.previewPaneVisible, true)
    }
}
