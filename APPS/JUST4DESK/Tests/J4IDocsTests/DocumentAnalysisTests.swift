import XCTest
@testable import J4IDocs

final class DocumentAnalysisTests: XCTestCase {
    func testMetadataScannerFindsDatesAmountsIdentifiers() {
        let text = "Factura nº 2026-004 del 12/03/2026 por un importe de 1.234,56 €. NIF: 12345678Z. IBAN: ES91 2100 0418 4502 0005 1332"
        let result = MetadataScanner.scan(text: text)
        XCTAssertTrue(result.dates.contains("12/03/2026"))
        XCTAssertTrue(result.amounts.contains("1.234,56 €"))
        XCTAssertTrue(result.identifiers.contains("12345678Z"))
        XCTAssertTrue(result.identifiers.contains { $0.hasPrefix("ES91") })
    }

    func testDocxXMLToText() {
        let xml = "<w:document><w:body><w:p><w:r><w:t>Hola </w:t></w:r><w:r><w:t>mundo</w:t></w:r></w:p><w:p><w:r><w:t>Factura &amp; recibo</w:t></w:r></w:p></w:body></w:document>"
        let text = TextExtractor.textFromDocumentXML(xml)
        XCTAssertEqual(text, "Hola mundo\nFactura & recibo")
    }

    func testTextExtractorReadsPlainText() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("j4i-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: url) }
        try "Contenido de prueba".write(to: url, atomically: true, encoding: .utf8)

        let result = TextExtractor.extract(from: url)
        XCTAssertEqual(result?.text, "Contenido de prueba")
        XCTAssertEqual(result?.hasTextLayer, true)
        XCTAssertEqual(result?.usedOCR, false)
    }

    func testAnalyzerComputesHashAndProfile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("j4i-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: url) }
        try "Nómina de marzo de 2026, importe 2.345,67 €".write(to: url, atomically: true, encoding: .utf8)

        let profile = DocumentAnalyzer.analyze(url: url)
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.fileExtension, "txt")
        XCTAssertEqual(profile?.contentHash.count, 64)
        XCTAssertTrue(profile?.amounts.contains("2.345,67 €") == true)
        XCTAssertFalse(profile?.textSample.isEmpty == true)
        XCTAssertEqual(profile?.usedOCR, false)
    }

    func testIgnoredFileNames() {
        XCTAssertTrue(SourceFolderWatcher.isIgnored(fileName: ".DS_Store"))
        XCTAssertTrue(SourceFolderWatcher.isIgnored(fileName: "descarga.pdf.part"))
        XCTAssertTrue(SourceFolderWatcher.isIgnored(fileName: "fichero~"))
        XCTAssertFalse(SourceFolderWatcher.isIgnored(fileName: "factura.pdf"))
    }

    func testAnalyzerProducesLiteProfileForUnsupportedFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("j4i-\(UUID().uuidString).exe")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data([0x4D, 0x5A, 0x90, 0x00, 0x03, 0x00]).write(to: url)   // cabecera MZ (binario)

        let profile = DocumentAnalyzer.analyze(url: url)
        XCTAssertNotNil(profile, "un binario debe producir perfil lite, no nil")
        XCTAssertEqual(profile?.fileExtension, "exe")
        XCTAssertEqual(profile?.textLength, 0)
        XCTAssertTrue(profile?.textSample.isEmpty == true)
        XCTAssertEqual(profile?.usedOCR, false)
        XCTAssertEqual(profile?.contentHash.count, 64)
    }
}
