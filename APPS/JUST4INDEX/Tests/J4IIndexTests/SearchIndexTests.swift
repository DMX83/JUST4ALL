import XCTest
@testable import J4IIndex

final class SearchIndexTests: XCTestCase {
    private var tempDir: URL!
    private var index: SearchIndex!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("j4i-index-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        index = SearchIndex(databaseURL: tempDir.appendingPathComponent("index.sqlite"))
    }

    override func tearDownWithError() throws {
        index = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Helpers

    private func entry(_ path: String, isDirectory: Bool = false, size: Int64 = 100) -> IndexEntryWrite {
        IndexEntryWrite(
            path: path,
            isDirectory: isDirectory,
            sizeBytes: size,
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private func makeRoot(_ name: String) async throws -> (root: IndexRoot, path: String) {
        let path = tempDir.appendingPathComponent(name, isDirectory: true).path
        let root = try await index.addRoot(path: path)
        return (root, path)
    }

    // MARK: - Búsqueda básica

    func testSearchPrefixAndDiacritics() async throws {
        let (root, path) = try await makeRoot("rootA")
        try await index.upsertEntries(rootID: root.id, [
            entry("\(path)/Nominas/Nómina-Marzo.pdf"),
            entry("\(path)/Nominas/Nomina-Abril.pdf"),
            entry("\(path)/Fotos/playa.jpg")
        ])

        let accented = try await index.search(IndexSearchRequest(query: "nómina"))
        XCTAssertEqual(Set(accented.map(\.entry.name)), ["Nómina-Marzo.pdf", "Nomina-Abril.pdf"])

        let unaccented = try await index.search(IndexSearchRequest(query: "nomina"))
        XCTAssertEqual(Set(unaccented.map(\.entry.name)), ["Nómina-Marzo.pdf", "Nomina-Abril.pdf"])

        let prefix = try await index.search(IndexSearchRequest(query: "nom"))
        XCTAssertEqual(prefix.count, 2)

        let partial = try await index.search(IndexSearchRequest(query: "abril"))
        XCTAssertEqual(partial.map(\.entry.name), ["Nomina-Abril.pdf"])

        let missing = try await index.search(IndexSearchRequest(query: "zzzz"))
        XCTAssertTrue(missing.isEmpty)
    }

    func testSearchFindsSubstringInsideTokens() async throws {
        let (root, path) = try await makeRoot("rootNet")
        try await index.upsertEntries(rootID: root.id, [
            entry("\(path)/Makefile.NetBSD"),
            entry("\(path)/dotnet-sdk-6.0.100-win-x64.exe"),
            entry("\(path)/Internet.Download.Manager.6.42.25.0", isDirectory: true),
            entry("\(path)/Fotos/playa.jpg")
        ])

        // El MATCH por prefijos solo ve «NetBSD»; la pasada «contiene» añade «dotnet», «Internet»…
        let hits = try await index.search(IndexSearchRequest(query: "net"))
        let names = hits.map(\.entry.name)
        XCTAssertTrue(names.contains("Makefile.NetBSD"))
        XCTAssertTrue(names.contains("dotnet-sdk-6.0.100-win-x64.exe"))
        XCTAssertTrue(names.contains("Internet.Download.Manager.6.42.25.0"))
        XCTAssertFalse(names.contains("playa.jpg"))
        XCTAssertEqual(names.first, "Makefile.NetBSD", "el match por prefijo rankea por delante")

        // Subcadena insensible a acentos: «diseño» se encuentra buscando «seno».
        try await index.upsertEntries(rootID: root.id, [entry("\(path)/Diseño-final.pdf")])
        let folded = try await index.search(IndexSearchRequest(query: "seno"))
        XCTAssertTrue(folded.contains { $0.entry.name == "Diseño-final.pdf" })
    }

    func testSearchMultiTermRequiresAllTerms() async throws {
        let (root, path) = try await rootWith(path: "rootA")
        try await index.upsertEntries(rootID: root.id, [
            entry("\(path)/Facturas/Factura-Luz-Marzo.pdf")
        ])

        let both = try await index.search(IndexSearchRequest(query: "factura marzo"))
        XCTAssertEqual(both.count, 1)

        let none = try await index.search(IndexSearchRequest(query: "factura agosto"))
        XCTAssertTrue(none.isEmpty)
    }

    func testSearchSanitizesFTSSyntax() async throws {
        let (root, path) = try await rootWith(path: "rootA")
        try await index.upsertEntries(rootID: root.id, [
            entry("\(path)/foobar.pdf")
        ])

        let weird = try await index.search(IndexSearchRequest(query: "foo\"*bar(baz)"))
        XCTAssertTrue(weird.isEmpty || weird.allSatisfy { $0.entry.name == "foobar.pdf" })

        let punctOnly = try await index.search(IndexSearchRequest(query: "***(((("))
        XCTAssertTrue(punctOnly.isEmpty)

        let stopwords = try await index.search(IndexSearchRequest(query: "factura AND luz"))
        XCTAssertTrue(stopwords.isEmpty)
    }

    func testFTSTermBuilder() {
        XCTAssertEqual(SearchIndex.ftsMatchExpression(from: "  Foo  Bar  "), "foo* AND bar*")
        XCTAssertNil(SearchIndex.ftsMatchExpression(from: "***"))
        XCTAssertEqual(SearchIndex.ftsMatchExpression(from: "factura AND luz"), "factura* AND luz*")
        XCTAssertEqual(SearchIndex.ftsMatchExpression(from: "informe-2026"), "informe* AND 2026*")
        XCTAssertEqual(SearchIndex.ftsMatchExpression(from: "factura.pdf"), "factura* AND pdf*")
    }

    // MARK: - Filtros

    func testSearchFilters() async throws {
        let (root, path) = try await rootWith(path: "rootA")
        try await index.upsertEntries(rootID: root.id, [
            entry("\(path)/01_Fiscal/Factura.pdf", size: 10),
            entry("\(path)/02_Fotos/playa.jpg", size: 5_000),
            entry("\(path)/02_Fotos", isDirectory: true),
            entry("\(path)/sub/contrato.txt", size: 50),
            entry("\(path)/contrato.txt", size: 50)
        ])

        var pdfFilters = IndexSearchFilters()
        pdfFilters.extensions = ["pdf"]
        let pdfOnly = try await index.search(IndexSearchRequest(query: "playa", filters: pdfFilters))
        XCTAssertTrue(pdfOnly.isEmpty, "playa.jpg no debe aparecer con filtro pdf")

        var jpgFilters = IndexSearchFilters()
        jpgFilters.extensions = ["jpg"]
        let jpgOnly = try await index.search(IndexSearchRequest(query: "playa", filters: jpgFilters))
        XCTAssertEqual(jpgOnly.count, 1)

        var dirFilters = IndexSearchFilters()
        dirFilters.directoriesOnly = true
        let dirsOnly = try await index.search(IndexSearchRequest(query: "fotos", filters: dirFilters))
        XCTAssertEqual(dirsOnly.map(\.entry.name), ["02_Fotos"])
        XCTAssertTrue(dirsOnly.allSatisfy(\.entry.isDirectory))

        var bigFilters = IndexSearchFilters()
        bigFilters.minSizeBytes = 1_000
        let big = try await index.search(IndexSearchRequest(query: "playa", filters: bigFilters))
        XCTAssertEqual(big.count, 1)
        var biggerFilters = IndexSearchFilters()
        biggerFilters.minSizeBytes = 10_000
        let tooBig = try await index.search(IndexSearchRequest(query: "playa", filters: biggerFilters))
        XCTAssertTrue(tooBig.isEmpty)

        var prefixFilters = IndexSearchFilters()
        prefixFilters.pathPrefix = "\(path)/sub"
        let scoped = try await index.search(IndexSearchRequest(query: "contrato", filters: prefixFilters))
        XCTAssertEqual(scoped.count, 1)
        XCTAssertTrue(scoped[0].entry.path.hasPrefix("\(path)/sub/"))
    }

    func testSearchScopedToRoot() async throws {
        let (rootA, pathA) = try await makeRoot("rootA")
        let (rootB, pathB) = try await makeRoot("rootB")
        try await index.upsertEntries(rootID: rootA.id, [entry("\(pathA)/informe.txt")])
        try await index.upsertEntries(rootID: rootB.id, [entry("\(pathB)/informe.txt")])

        let all = try await index.search(IndexSearchRequest(query: "informe"))
        XCTAssertEqual(all.count, 2)

        var filters = IndexSearchFilters()
        filters.rootID = rootB.id
        let scoped = try await index.search(IndexSearchRequest(query: "informe", filters: filters))
        XCTAssertEqual(scoped.count, 1)
        XCTAssertTrue(scoped[0].entry.path.hasPrefix(pathB))
        XCTAssertEqual(scoped[0].entry.rootID, rootB.id)
    }

    func testSearchLimit() async throws {
        let (root, path) = try await rootWith(path: "rootA")
        let writes = (1...6).map { entry("\(path)/doc-\($0).txt") }
        try await index.upsertEntries(rootID: root.id, writes)

        let limited = try await index.search(IndexSearchRequest(query: "doc", limit: 3))
        XCTAssertEqual(limited.count, 3)
    }

    // MARK: - Escritura

    func testUpsertReplacesPathWithoutDuplicates() async throws {
        let (root, path) = try await rootWith(path: "rootA")
        try await index.upsertEntries(rootID: root.id, [entry("\(path)/unico.pdf", size: 10)])
        try await index.upsertEntries(rootID: root.id, [entry("\(path)/unico.pdf", size: 99)])

        let hits = try await index.search(IndexSearchRequest(query: "unico"))
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].entry.sizeBytes, 99)
        let count = try await index.entryCount(rootID: root.id)
        XCTAssertEqual(count, 1)
    }

    func testRemoveEntriesDeletesSubtree() async throws {
        let (root, path) = try await rootWith(path: "rootA")
        try await index.upsertEntries(rootID: root.id, [
            entry("\(path)/carpeta", isDirectory: true),
            entry("\(path)/carpeta/a.txt"),
            entry("\(path)/carpeta/sub/b.txt"),
            entry("\(path)/otro.txt")
        ])

        let removed = try await index.removeEntries(rootID: root.id, paths: ["\(path)/carpeta"])
        XCTAssertEqual(removed, 3)
        let remaining = try await index.search(IndexSearchRequest(query: "txt"))
        XCTAssertEqual(remaining.map(\.entry.name), ["otro.txt"])
    }

    func testClearEntriesKeepsRoot() async throws {
        let (root, path) = try await rootWith(path: "rootA")
        try await index.upsertEntries(rootID: root.id, [entry("\(path)/a.txt"), entry("\(path)/b.txt")])

        try await index.clearEntries(rootID: root.id)
        let remaining = try await index.entryCount(rootID: root.id)
        XCTAssertEqual(remaining, 0)
        let roots = try await index.allRoots()
        XCTAssertEqual(roots.count, 1)
    }

    func testRemoveRootDeletesEverything() async throws {
        let (root, path) = try await rootWith(path: "rootA")
        try await index.upsertEntries(rootID: root.id, [entry("\(path)/a.txt")])

        try await index.removeRoot(id: root.id)
        let roots = try await index.allRoots()
        XCTAssertTrue(roots.isEmpty)
        let stats = try await index.stats()
        XCTAssertEqual(stats.totalEntries, 0)
    }

    // MARK: - Estado del root

    func testRootStatusAndEventIDs() async throws {
        let (root, path) = try await rootWith(path: "rootA")
        var status = try await index.rootStatus(id: root.id)
        XCTAssertEqual(status.state, .pending)
        XCTAssertNil(status.lastEventID)
        XCTAssertEqual(status.entryCount, 0)

        try await index.setRootState(id: root.id, state: .crawling)
        try await index.setLastEventID(42_424, forRoot: root.id)
        try await index.upsertEntries(rootID: root.id, [entry("\(path)/a.txt")])
        status = try await index.rootStatus(id: root.id)
        XCTAssertEqual(status.state, .crawling)
        XCTAssertEqual(status.lastEventID, 42_424)
        XCTAssertEqual(status.entryCount, 1)

        try await index.setRootState(id: root.id, state: .ready)
        status = try await index.rootStatus(id: root.id)
        XCTAssertEqual(status.state, .ready)
    }

    // MARK: - Contenido

    func testDocumentTextAndContentSearch() async throws {
        let (root, path) = try await rootWith(path: "rootA")
        try await index.upsertEntries(rootID: root.id, [entry("\(path)/informe.pdf")])
        let hits = try await index.search(IndexSearchRequest(query: "informe"))
        XCTAssertEqual(hits.count, 1)
        let entryID = hits[0].entry.id

        try await index.setDocumentText(
            entryID: entryID,
            text: "Contrato de alquiler con vencimiento en junio de dos mil veintiseis"
        )
        let storedText = try await index.documentText(entryID: entryID)
        XCTAssertEqual(storedText?.isEmpty, false)

        let nameOnly = try await index.search(IndexSearchRequest(query: "vencimiento"))
        XCTAssertTrue(nameOnly.isEmpty, "sin includeContent no debe encontrar texto interno")

        let withContent = try await index.search(IndexSearchRequest(query: "vencimiento", includeContent: true))
        XCTAssertEqual(withContent.count, 1)
        XCTAssertTrue(withContent[0].matchedContent)
        XCTAssertEqual(withContent[0].entry.id, entryID)
        XCTAssertEqual(withContent[0].contentSnippet?.contains("vencimiento"), true, "el fragmento debe contener la coincidencia")

        let nameMatch = try await index.search(IndexSearchRequest(query: "informe", includeContent: true))
        XCTAssertEqual(nameMatch.count, 1)
        XCTAssertFalse(nameMatch[0].matchedContent, "el match por nombre prevalece")
        XCTAssertNil(nameMatch[0].contentSnippet)
    }

    // MARK: - Helpers privados

    private func rootWith(path name: String) async throws -> (root: IndexRoot, path: String) {
        try await makeRoot(name)
    }
}
