import XCTest
@testable import JUST4DESK

/// Ordenación de la cola de revisión (F7.7): extensión → nombre, nombre, fecha y tamaño.
final class ReviewSortingTests: XCTestCase {
    private func item(_ name: String, sizeBytes: Int64 = 0, modifiedAt: Date? = nil, isDirectory: Bool = false, folderSummary: String? = nil) -> ReviewViewModel.Item {
        ReviewViewModel.Item(
            path: "/cuarentena/\(name)",
            name: name,
            sizeBytes: sizeBytes,
            modifiedAt: modifiedAt,
            suggestion: nil,
            destination: nil,
            isDirectory: isDirectory,
            folderSummary: folderSummary
        )
    }

    func testSortByExtensionKeepsGroupsAndPutsExtensionlessLast() {
        let items = [
            item("zeta.pdf"),
            item("alpha.exe"),
            item("beta.pdf"),
            item("notas")
        ]
        let sorted = ReviewViewModel.sorted(items, by: .ext)
        XCTAssertEqual(sorted.map(\.name), ["alpha.exe", "beta.pdf", "zeta.pdf", "notas"])
    }

    func testSortByNameIsAlphabetical() {
        let items = [item("b.txt"), item("a.txt"), item("c.txt")]
        let sorted = ReviewViewModel.sorted(items, by: .name)
        XCTAssertEqual(sorted.map(\.name), ["a.txt", "b.txt", "c.txt"])
    }

    func testSortByDatePutsNewestFirstAndUndatedLast() {
        let old = Date(timeIntervalSince1970: 1_000)
        let new = Date(timeIntervalSince1970: 2_000)
        let items = [
            item("antiguo.txt", modifiedAt: old),
            item("sin-fecha.txt", modifiedAt: nil),
            item("reciente.txt", modifiedAt: new)
        ]
        let sorted = ReviewViewModel.sorted(items, by: .date)
        XCTAssertEqual(sorted.map(\.name), ["reciente.txt", "antiguo.txt", "sin-fecha.txt"])
    }

    func testSortBySizePutsLargestFirst() {
        let items = [
            item("pequeno.txt", sizeBytes: 10),
            item("grande.txt", sizeBytes: 1_000),
            item("mediano.txt", sizeBytes: 100)
        ]
        let sorted = ReviewViewModel.sorted(items, by: .size)
        XCTAssertEqual(sorted.map(\.name), ["grande.txt", "mediano.txt", "pequeno.txt"])
    }

    func testExtensionGroupsSeparateFoldersFromExtensionlessFiles() {
        // Ajuste 24-sep: las carpetas de la cuarentena van a su propio grupo «CARPETAS»
        // (antes se mezclaban bajo «SIN EXTENSIÓN») y conservan su resumen de contenido.
        let items = [
            item("zeta.pdf"),
            item("Documents", isDirectory: true, folderSummary: "16 fichero(s) · dominante .pdf"),
            item("notas"),
            item("AnyUkit", isDirectory: true, folderSummary: "sin ficheros (cáscara vacía)")
        ]
        let groups = ReviewViewModel.extensionGroups(from: items)
        XCTAssertEqual(groups.first?.title, "CARPETAS (2)")
        XCTAssertEqual(groups.first?.items.map(\.name), ["AnyUkit", "Documents"])
        XCTAssertTrue(groups.contains { $0.title == "PDF (1)" })
        XCTAssertEqual(groups.last?.title, "SIN EXTENSIÓN (1)")
        XCTAssertEqual(groups.last?.items.map(\.name), ["notas"])
    }
}
