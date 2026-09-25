import XCTest
@testable import J4IFiling
import J4IIndex

/// G2 — detectores de sugerencias proactivas: capturas sueltas, candidatos a duplicado por
/// tamaño y grandes/olvidados (mapeo del índice). Todo barato, sin efectos secundarios.
final class ProactiveSuggestionTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("j4i-suggestions-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func write(_ name: String, bytes: Int) throws {
        try Data(repeating: 0x41, count: bytes).write(to: tempDir.appendingPathComponent(name))
    }

    func testScreenshotsDetectsSpanishAndEnglishNames() throws {
        try write("Captura de pantalla 2026-06-16 a las 21.20.16.png", bytes: 2048)
        try write("Screenshot_2026-01-02.png", bytes: 1024)
        try write("informe.pdf", bytes: 512)
        try write("Screenshot nota.txt", bytes: 64)
        try write(".Screenshot oculta.png", bytes: 32)

        let items = ProactiveSuggestionScanner.screenshots(in: [tempDir])
        XCTAssertEqual(
            items.map(\.name).sorted(),
            ["Captura de pantalla 2026-06-16 a las 21.20.16.png", "Screenshot_2026-01-02.png"].sorted(),
            "solo capturas de imagen visibles, sin ocultos ni otras extensiones"
        )
    }

    func testSizeMatchedCandidatesFilterSizesAndPartialDownloads() throws {
        try write("duplicado-grande.bin", bytes: 4096)
        try write("pequeno.bin", bytes: 512)
        try write("incompleto.bin.part", bytes: 4096)

        let items = ProactiveSuggestionScanner.sizeMatchedCandidates(in: [tempDir], knownSizes: [4096, 512], minSizeBytes: 1024)
        XCTAssertEqual(items.map(\.name), ["duplicado-grande.bin"], "≥ mínimo, tamaño conocido y sin descargas parciales")
    }

    func testLargeForgottenMapsIndexEntries() async throws {
        let dbDir = tempDir.appendingPathComponent("db", isDirectory: true)
        try FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)
        let index = SearchIndex(databaseURL: dbDir.appendingPathComponent("index.sqlite"))
        let root = tempDir.appendingPathComponent("archive", isDirectory: true).path
        let rootEntry = try await index.addRoot(path: root)
        let old = Date(timeIntervalSince1970: 1_400_000_000)
        try await index.upsertEntries(rootID: rootEntry.id, [
            IndexEntryWrite(path: "\(root)/pelicula.mkv", isDirectory: false, sizeBytes: 2_000_000_000, modifiedAt: old)
        ])

        let cutoff = Date(timeIntervalSince1970: 1_600_000_000)
        let entries = try await index.largeFiles(minBytes: 1_000_000_000, olderThan: cutoff, limit: 10)
        let suggestion = ProactiveSuggestionScanner.largeForgottenSuggestion(entries: entries)
        XCTAssertEqual(suggestion?.kind, .largeForgotten)
        XCTAssertEqual(suggestion?.items.first?.name, "pelicula.mkv")
        XCTAssertEqual(suggestion?.items.first?.sizeBytes, 2_000_000_000)
    }

    func testBuildersReturnNilWhenEmpty() {
        XCTAssertNil(ProactiveSuggestionScanner.screenshotSuggestion(folders: [tempDir], labels: ["tmp"]))
        XCTAssertNil(ProactiveSuggestionScanner.duplicateSuggestion(folders: [tempDir], labels: ["tmp"], knownSizes: []))
        XCTAssertNil(ProactiveSuggestionScanner.largeForgottenSuggestion(entries: []))
    }

    func testContextLabelGrammar() {
        XCTAssertEqual(ProactiveSuggestionScanner.contextLabel([]), "")
        XCTAssertEqual(ProactiveSuggestionScanner.contextLabel(["A"]), "En «A»")
        XCTAssertEqual(ProactiveSuggestionScanner.contextLabel(["A", "B"]), "En «A» y «B»")
        XCTAssertEqual(ProactiveSuggestionScanner.contextLabel(["A", "B", "C"]), "En «A», «B» y «C»")
    }
}
