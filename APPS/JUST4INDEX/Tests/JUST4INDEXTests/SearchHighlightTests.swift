import XCTest
@testable import JUST4INDEX

final class SearchHighlightTests: XCTestCase {
    func testHighlightRangesBasic() {
        let text = "Factura-Luz-Marzo.pdf"
        let ranges = SearchHighlight.ranges(in: text, terms: ["factura"])
        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual(String(text[ranges[0]]), "Factura")
    }

    func testHighlightRangesDiacriticsInsensitive() {
        let text = "Nómina-Abril.pdf"
        let ranges = SearchHighlight.ranges(in: text, terms: ["nomina"])
        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual(String(text[ranges[0]]), "Nómina")
    }

    func testHighlightRangesMultipleTermsAreSortedAndMerged() {
        let text = "informe-2026.pdf"
        let ranges = SearchHighlight.ranges(in: text, terms: ["2026", "informe"])
        XCTAssertEqual(ranges.count, 2)
        XCTAssertEqual(String(text[ranges[0]]), "informe")
        XCTAssertEqual(String(text[ranges[1]]), "2026")
    }

    func testHighlightRangesOverlappingTermsDoNotDuplicate() {
        let text = "contrato-contrato.pdf"
        let ranges = SearchHighlight.ranges(in: text, terms: ["contrato", "contrat"])
        XCTAssertEqual(ranges.count, 2)
        XCTAssertEqual(String(text[ranges[0]]), "contrato")
        XCTAssertEqual(String(text[ranges[1]]), "contrato")
    }

    func testHighlightRangesEmptyWhenNoMatch() {
        let text = "sin coincidencias"
        XCTAssertTrue(SearchHighlight.ranges(in: text, terms: ["zzz"]).isEmpty)
        XCTAssertTrue(SearchHighlight.ranges(in: text, terms: []).isEmpty)
        XCTAssertTrue(SearchHighlight.ranges(in: text, terms: ["  "]).isEmpty)
    }

    func testKindFilterExtensions() {
        XCTAssertNil(SearchViewModel.ResultKindFilter.all.extensions)
        XCTAssertTrue(SearchViewModel.ResultKindFilter.documents.extensions?.contains("pdf") == true)
        XCTAssertTrue(SearchViewModel.ResultKindFilter.images.extensions?.contains("png") == true)
        XCTAssertTrue(SearchViewModel.ResultKindFilter.archives.extensions?.contains("zip") == true)
    }
}
