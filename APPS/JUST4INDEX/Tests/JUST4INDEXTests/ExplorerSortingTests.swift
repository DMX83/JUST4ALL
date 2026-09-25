import XCTest
@testable import J4IIndex
@testable import JUST4INDEX

/// Orden y filtro del explorador (F8.0): nombre, tamaño, fecha y exclusión de carpetas.
final class ExplorerSortingTests: XCTestCase {
    private func file(_ name: String, size: Int64 = 0, date: Date? = nil) -> IndexEntry {
        IndexEntry(
            id: Int64.random(in: 1...100_000),
            rootID: 1,
            path: "/x/\(name)",
            name: name,
            ext: (name as NSString).pathExtension,
            isDirectory: false,
            sizeBytes: size,
            modifiedAt: date
        )
    }

    private func folder(_ name: String) -> IndexEntry {
        IndexEntry(
            id: Int64.random(in: 1...100_000),
            rootID: 1,
            path: "/x/\(name)",
            name: name,
            ext: "",
            isDirectory: true,
            sizeBytes: 0,
            modifiedAt: nil
        )
    }

    func testVisibleFilesFiltersAndSortsByNameExcludingFolders() {
        let entries = [
            file("zeta.pdf"),
            file("beta.pdf"),
            file("alfa.pdf"),
            folder("carpeta")
        ]
        let sorted = ExplorerViewModel.visibleFiles(from: entries, filter: "", sort: .name)
        XCTAssertEqual(sorted.map(\.name), ["alfa.pdf", "beta.pdf", "zeta.pdf"])
        let filtered = ExplorerViewModel.visibleFiles(from: entries, filter: "ta", sort: .name)
        XCTAssertEqual(filtered.map(\.name), ["beta.pdf", "zeta.pdf"])
    }

    func testVisibleFilesSortsBySizeDescending() {
        let entries = [
            file("pequeno.txt", size: 10),
            file("grande.txt", size: 1_000),
            file("mediano.txt", size: 100)
        ]
        let sorted = ExplorerViewModel.visibleFiles(from: entries, filter: "", sort: .size)
        XCTAssertEqual(sorted.map(\.name), ["grande.txt", "mediano.txt", "pequeno.txt"])
    }

    func testVisibleFilesSortsByDateNewestFirstWithUndatedLast() {
        let old = Date(timeIntervalSince1970: 1_000)
        let recent = Date(timeIntervalSince1970: 2_000)
        let entries = [
            file("antiguo.txt", date: old),
            file("sin-fecha.txt", date: nil),
            file("reciente.txt", date: recent)
        ]
        let sorted = ExplorerViewModel.visibleFiles(from: entries, filter: "", sort: .date)
        XCTAssertEqual(sorted.map(\.name), ["reciente.txt", "antiguo.txt", "sin-fecha.txt"])
    }

    // MARK: - Árbol de carpetas (F8.2)

    private func dirEntry(_ name: String, id: Int64) -> IndexEntry {
        IndexEntry(id: id, rootID: 1, path: "/x/\(name)", name: name, ext: "", isDirectory: true, sizeBytes: 0, modifiedAt: nil)
    }

    func testVisibleTreeRowsHonoursExpansion() {
        let c = ExplorerViewModel.FolderNode(entry: dirEntry("C", id: 3), children: [])
        let b = ExplorerViewModel.FolderNode(entry: dirEntry("B", id: 2), children: [c])
        let a = ExplorerViewModel.FolderNode(entry: dirEntry("A", id: 1), children: [b])
        let d = ExplorerViewModel.FolderNode(entry: dirEntry("D", id: 4), children: [])

        let collapsed = ExplorerViewModel.visibleRows(of: [a, d], expanded: [])
        XCTAssertEqual(collapsed.map(\.node.entry.name), ["A", "D"])

        let expandedA = ExplorerViewModel.visibleRows(of: [a, d], expanded: [1])
        XCTAssertEqual(expandedA.map(\.node.entry.name), ["A", "B", "D"])
        XCTAssertEqual(expandedA.map(\.depth), [0, 1, 0])

        let expandedAB = ExplorerViewModel.visibleRows(of: [a, d], expanded: [1, 2])
        XCTAssertEqual(expandedAB.map(\.node.entry.name), ["A", "B", "C", "D"])
    }
}
