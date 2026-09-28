import XCTest
@testable import J4ICore

/// G5.1 — etiquetas nativas del Finder (xattr `com.apple.metadata:_kMDItemUserTags`).
final class FinderTagsTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("j4i-tags-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeFile(_ name: String = "nota.txt") throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try "hola".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testAddReadRemoveRoundTrip() throws {
        let file = try makeFile()
        XCTAssertEqual(FinderTags.names(of: file), [])

        XCTAssertEqual(FinderTags.add(["Trading"], to: file), .updated)
        XCTAssertEqual(FinderTags.names(of: file), ["Trading"])

        XCTAssertEqual(FinderTags.add(["Trading"], to: file), .unchanged, "no duplica")

        XCTAssertEqual(FinderTags.add(["Fiscal 2026"], to: file), .updated, "fusiona con lo existente")
        XCTAssertEqual(FinderTags.names(of: file), ["Trading", "Fiscal 2026"])

        XCTAssertEqual(FinderTags.remove(["Trading"], from: file), .updated)
        XCTAssertEqual(FinderTags.names(of: file), ["Fiscal 2026"])

        XCTAssertEqual(FinderTags.remove(["Fiscal 2026"], from: file), .updated)
        XCTAssertEqual(FinderTags.names(of: file), [], "sin etiquetas, el atributo se elimina")

        XCTAssertEqual(FinderTags.remove(["Nada"], from: file), .unchanged)
    }

    func testColoredTagIsReadByName() throws {
        let file = try makeFile()
        // Formato real del Finder para una etiqueta con color: «Nombre\nÍndice».
        XCTAssertTrue(FinderTags.setRawTags(["Proyecto\n6"], of: file))
        XCTAssertEqual(FinderTags.names(of: file), ["Proyecto"])
        XCTAssertEqual(FinderTags.add(["Proyecto"], to: file), .unchanged, "el color no genera duplicado")
        XCTAssertEqual(FinderTags.remove(["Proyecto"], from: file), .updated)
        XCTAssertEqual(FinderTags.names(of: file), [])
    }

    func testBatchApplyCountsMissingsAsFailures() throws {
        let a = try makeFile("a.txt")
        let b = try makeFile("b.txt")
        let missing = tempDir.appendingPathComponent("no-existe.txt")

        let written = FinderTags.apply(["Trading"], to: [a, b, missing])
        XCTAssertEqual(written.updated, 2)
        XCTAssertEqual(written.failed, 1)
        XCTAssertEqual(written.unchanged, 0)
        XCTAssertEqual(FinderTags.names(of: a), ["Trading"])
        XCTAssertEqual(FinderTags.names(of: b), ["Trading"])

        let removed = FinderTags.apply(["Trading"], to: [a, b, missing], removing: true)
        XCTAssertEqual(removed.updated, 2)
        XCTAssertEqual(removed.failed, 1)
        XCTAssertEqual(FinderTags.names(of: a), [])
    }

    func testEmptyNamesAreNoOp() throws {
        let file = try makeFile()
        XCTAssertEqual(FinderTags.add(["  "], to: file), .unchanged)
        XCTAssertEqual(FinderTags.remove([""], from: file), .unchanged)
        XCTAssertEqual(FinderTags.names(of: file), [])
    }

    func testEntriesExposeColorIndex() throws {
        let file = try makeFile()
        XCTAssertTrue(FinderTags.setRawTags(["Proyecto\n6", "SinColor"], of: file))
        let entries = FinderTags.entries(of: file)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0], FinderTags.TagEntry(name: "Proyecto", colorIndex: 6))
        XCTAssertEqual(entries[1], FinderTags.TagEntry(name: "SinColor", colorIndex: 0))
    }

    func testAddColoredWritesFinderFormatAndUpdatesColor() throws {
        let file = try makeFile()
        XCTAssertEqual(FinderTags.addColored([FinderTags.TagEntry(name: "Rojo", colorIndex: 6)], to: file), .updated)
        XCTAssertTrue(FinderTags.setRawTags(["Rojo\n6"], of: file), "formato esperado con color")

        // Mismo nombre, nuevo color: se actualiza sin duplicar.
        XCTAssertEqual(FinderTags.addColored([FinderTags.TagEntry(name: "Rojo", colorIndex: 7)], to: file), .updated)
        XCTAssertEqual(FinderTags.entries(of: file), [FinderTags.TagEntry(name: "Rojo", colorIndex: 7)])

        // Aditivo: otra etiqueta no toca la existente.
        XCTAssertEqual(FinderTags.addColored([FinderTags.TagEntry(name: "Azul", colorIndex: 4)], to: file), .updated)
        let names = FinderTags.entries(of: file).map(\.name).sorted()
        XCTAssertEqual(names, ["Azul", "Rojo"])
    }
}
