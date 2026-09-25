import XCTest
@testable import J4IIndex

final class ExplorerIndexTests: XCTestCase {
    private var tempDir: URL!
    private var index: SearchIndex!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("j4i-explorer-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        index = SearchIndex(databaseURL: tempDir.appendingPathComponent("index.sqlite"))
    }

    override func tearDownWithError() throws {
        index = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func entry(_ path: String, isDirectory: Bool = false, size: Int64 = 100) -> IndexEntryWrite {
        IndexEntryWrite(
            path: path,
            isDirectory: isDirectory,
            sizeBytes: size,
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    func testChildrenOfDirectoryReturnsDirectChildrenOnly() async throws {
        let path = tempDir.appendingPathComponent("rootA", isDirectory: true).path
        let root = try await index.addRoot(path: path)
        try await index.upsertEntries(rootID: root.id, [
            entry("\(path)/01_Fiscal", isDirectory: true),
            entry("\(path)/01_Fiscal/Factura-Luz.pdf"),
            entry("\(path)/01_Fiscal/sub", isDirectory: true),
            entry("\(path)/01_Fiscal/sub/deep.pdf"),
            entry("\(path)/leeme.txt")
        ])

        let children = try await index.children(ofDirectory: "\(path)/01_Fiscal")
        XCTAssertEqual(children.count, 2, "no debe incluir nietos (deep.pdf)")
        XCTAssertEqual(children.map(\.name), ["sub", "Factura-Luz.pdf"], "carpetas primero, luego ficheros")

        let rootChildren = try await index.children(ofDirectory: path)
        XCTAssertEqual(Set(rootChildren.map(\.name)), ["01_Fiscal", "leeme.txt"])
    }

    func testChildrenOfEmptyOrUnknownDirectoryIsEmpty() async throws {
        let path = tempDir.appendingPathComponent("rootB", isDirectory: true).path
        _ = try await index.addRoot(path: path)
        let children = try await index.children(ofDirectory: path)
        XCTAssertTrue(children.isEmpty)

        let unknown = try await index.children(ofDirectory: "\(path)/no-existe")
        XCTAssertTrue(unknown.isEmpty)
    }

    func testSubtreeStatsCountsFilesSizeAndSkipsHidden() async throws {
        let path = tempDir.appendingPathComponent("rootC", isDirectory: true).path
        let root = try await index.addRoot(path: path)
        try await index.upsertEntries(rootID: root.id, [
            entry("\(path)/01_Fiscal", isDirectory: true),
            entry("\(path)/01_Fiscal/Factura.pdf", size: 1_000),
            entry("\(path)/01_Fiscal/sub", isDirectory: true),
            entry("\(path)/01_Fiscal/sub/deep.pdf", size: 2_000),
            entry("\(path)/01_Fiscal/.DS_Store", size: 6_000)
        ])

        let stats = try await index.subtreeStats(forDirectory: "\(path)/01_Fiscal")
        XCTAssertEqual(stats.fileCount, 2, "los ocultos no cuentan")
        XCTAssertEqual(stats.directoryCount, 1)
        XCTAssertEqual(stats.totalSizeBytes, 3_000)

        let empty = try await index.subtreeStats(forDirectory: "\(path)/01_Fiscal/sub")
        XCTAssertEqual(empty.fileCount, 1)
        XCTAssertEqual(empty.directoryCount, 0)
    }
}
