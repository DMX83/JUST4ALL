import XCTest
@testable import J4IIndex

/// N8 — operadores de búsqueda (`ext:`, `tipo:`, `fecha:`) y listado por filtros.
final class SearchOperatorsTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    // MARK: - Parseo

    func testExtensionsAccumulateAndTrimDots() {
        let parsed = SearchQueryParser.parse("recibo ext:.pdf,doc ext:xlsx", calendar: utc)
        XCTAssertEqual(parsed.text, "recibo")
        XCTAssertEqual(parsed.extensions, ["pdf", "doc", "xlsx"])
        XCTAssertTrue(parsed.hasFilters)
    }

    func testKindFamiliesWithAliasesAndAccents() {
        let video = SearchQueryParser.parse("tipo:vídeo", calendar: utc)
        XCTAssertEqual(video.extensions, SearchQueryParser.kindExtensions(for: "video"))
        XCTAssertEqual(video.text, "")

        let images = SearchQueryParser.parse("tipo:Imágenes", calendar: utc)
        XCTAssertEqual(images.extensions, SearchQueryParser.kindExtensions(for: "imagenes"))

        XCTAssertTrue(SearchQueryParser.parse("tipo:documentos", calendar: utc).extensions?.contains("pdf") == true)
        XCTAssertTrue(SearchQueryParser.parse("tipo:comprimidos", calendar: utc).extensions?.contains("zip") == true)
    }

    func testExtensionAndKindIntersect() {
        let parsed = SearchQueryParser.parse("tipo:documentos ext:pdf", calendar: utc)
        XCTAssertEqual(parsed.extensions, ["pdf"], "ext: y tipo: juntos = intersección")
    }

    func testDateMonthRange() {
        let parsed = SearchQueryParser.parse("fecha:2026-09", calendar: utc)
        XCTAssertEqual(parsed.text, "")
        let start = utc.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        XCTAssertEqual(parsed.modifiedAfter, start)
        XCTAssertEqual(parsed.modifiedBefore, start.addingTimeInterval(30 * 24 * 3600 - 1), "fin inclusivo: último segundo de septiembre")
    }

    func testDateYearRange() {
        let parsed = SearchQueryParser.parse("fecha:2026", calendar: utc)
        let start = utc.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        XCTAssertEqual(parsed.modifiedAfter, start)
        XCTAssertEqual(parsed.modifiedBefore, utc.date(byAdding: .year, value: 1, to: start)!.addingTimeInterval(-1))
    }

    func testUnknownAndInvalidTokensStayAsText() {
        let unknown = SearchQueryParser.parse("foo:bar acta", calendar: utc)
        XCTAssertEqual(unknown.text, "foo:bar acta")
        XCTAssertFalse(unknown.hasFilters)

        let invalid = SearchQueryParser.parse("fecha:muy-ayer", calendar: utc)
        XCTAssertEqual(invalid.text, "fecha:muy-ayer")
        XCTAssertFalse(invalid.hasFilters)
    }

    // MARK: - Listado por filtros (integración)

    func testListByFiltersUsesExtensionsAndDates() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("j4i-ops-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let index = SearchIndex(databaseURL: tempDir.appendingPathComponent("index.sqlite"))
        let rootPath = tempDir.appendingPathComponent("rootA", isDirectory: true).path
        let root = try await index.addRoot(path: rootPath)
        let sepDate = utc.date(from: DateComponents(year: 2026, month: 9, day: 10))!
        let augDate = utc.date(from: DateComponents(year: 2026, month: 8, day: 10))!
        try await index.upsertEntries(rootID: root.id, [
            IndexEntryWrite(path: "\(rootPath)/factura-sep.pdf", isDirectory: false, sizeBytes: 10, modifiedAt: sepDate),
            IndexEntryWrite(path: "\(rootPath)/foto-sep.jpg", isDirectory: false, sizeBytes: 10, modifiedAt: sepDate),
            IndexEntryWrite(path: "\(rootPath)/factura-ago.pdf", isDirectory: false, sizeBytes: 10, modifiedAt: augDate)
        ])

        var extensionFilters = IndexSearchFilters()
        extensionFilters.extensions = ["pdf"]
        let pdfs = try await index.listByFilters(filters: extensionFilters)
        XCTAssertEqual(pdfs.map(\.entry.name).sorted(), ["factura-ago.pdf", "factura-sep.pdf"], "solo pdf")

        let month = SearchQueryParser.parse("fecha:2026-09", calendar: utc)
        var dateFilters = IndexSearchFilters()
        dateFilters.modifiedAfter = month.modifiedAfter
        dateFilters.modifiedBefore = month.modifiedBefore
        let september = try await index.listByFilters(filters: dateFilters)
        XCTAssertEqual(september.map(\.entry.name).sorted(), ["factura-sep.pdf", "foto-sep.jpg"], "solo los modificados en septiembre")
    }
}
