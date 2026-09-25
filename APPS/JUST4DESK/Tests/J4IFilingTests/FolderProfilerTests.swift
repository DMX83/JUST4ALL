import XCTest
@testable import J4IFiling

/// Ajuste 2026-09-24: las carpetas-cáscara (sin ficheros, aunque contengan subcarpetas vacías —
/// p. ej. «AnyUkit» con music/video vacíos) deben detectarse como vacías y no acabar en «sin clasificar».
final class FolderProfilerTests: XCTestCase {
    func testFolderWithOnlyEmptySubfoldersIsEmptyShell() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("j4i-shell-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("music"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("video"), withIntermediateDirectories: true)

        let summary = FolderProfiler.summarize(folderURL: root, includeText: false)
        XCTAssertTrue(summary.isEmpty, "sin ficheros en el árbol = cáscara vacía (no «sin clasificar»)")
        XCTAssertEqual(summary.fileCount, 0)
        XCTAssertEqual(summary.directoryCount, 2)
    }

    func testFolderWithFilesProfilesDominantExtensionWithoutReadingText() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("j4i-profile-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for name in ["a.pdf", "b.pdf", "notas.txt"] {
            try "contenido".write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }

        let summary = FolderProfiler.summarize(folderURL: root, includeText: false)
        XCTAssertFalse(summary.isEmpty)
        XCTAssertEqual(summary.fileCount, 3)
        XCTAssertEqual(summary.dominantExtension, "pdf")
        XCTAssertTrue(summary.textSample.isEmpty, "includeText:false no debe leer texto de documentos")
    }
}
