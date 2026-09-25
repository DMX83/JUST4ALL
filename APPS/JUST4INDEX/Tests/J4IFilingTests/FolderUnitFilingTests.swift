import XCTest
import J4ICore
import J4IIndex
@testable import J4IFiling

final class FolderUnitFilingTests: XCTestCase {
    func testFolderUnitMovesWholeTreeClassifiedByContent() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("j4i-folder-unit-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let rootURL = tempDir.appendingPathComponent("organizado", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let sourceDir = tempDir.appendingPathComponent("entrada", isDirectory: true)
        let movieFolder = sourceDir.appendingPathComponent("Above Majestic Documental Completo", isDirectory: true)
        try FileManager.default.createDirectory(at: movieFolder, withIntermediateDirectories: true)
        try "video".write(to: movieFolder.appendingPathComponent("documental.mp4"), atomically: true, encoding: .utf8)
        try "subs".write(to: movieFolder.appendingPathComponent("subtitulos.srt"), atomically: true, encoding: .utf8)

        let index = SearchIndex(databaseURL: tempDir.appendingPathComponent("index.sqlite"))
        _ = try await index.addRoot(path: rootURL.path)

        let coordinator = FilingCoordinator(
            index: index,
            rootURL: rootURL,
            knowledge: LocalKnowledgeStore(fileURL: tempDir.appendingPathComponent("knowledge.json"))
        )
        let outcome = await coordinator.processItem(at: movieFolder)

        // Clasificación: «documental» en el nombre → 13_Multimedia/Documentales (taxonomía fina F9.2).
        XCTAssertEqual(outcome.action, "move")
        XCTAssertEqual(outcome.categoryPath, "13_Multimedia/Documentales")

        // La carpeta viaja ENTERA, conservando su nombre y su contenido.
        XCTAssertFalse(FileManager.default.fileExists(atPath: movieFolder.path), "el original ya no está en origen")
        let destination = URL(fileURLWithPath: outcome.destinationPath)
        XCTAssertEqual(destination.lastPathComponent, "Above Majestic Documental Completo")
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("documental.mp4").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("subtitulos.srt").path))

        // La carpeta queda indexada con su resumen.
        let entryID = try? await index.entryID(path: destination.path)
        XCTAssertNotNil(entryID, "la carpeta archivada debe estar en el índice")

        // Journal + undo restauran la carpeta completa.
        let journal = try await index.journalRecent(limit: 10)
        XCTAssertEqual(journal.count, 1)
        XCTAssertEqual(journal[0].action, "move")
        XCTAssertEqual(journal[0].destinationPath, outcome.destinationPath)
        XCTAssertTrue(journal[0].isUndoable)

        let undone = await coordinator.undo(entry: journal[0])
        XCTAssertTrue(undone)
        XCTAssertTrue(FileManager.default.fileExists(atPath: movieFolder.appendingPathComponent("documental.mp4").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testFolderUnitWithoutSignalGoesToQuarantineWhole() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("j4i-folder-quarantine-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let rootURL = tempDir.appendingPathComponent("organizado", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let sourceDir = tempDir.appendingPathComponent("entrada", isDirectory: true)
        let weirdFolder = sourceDir.appendingPathComponent("Paquete Raro", isDirectory: true)
        try FileManager.default.createDirectory(at: weirdFolder, withIntermediateDirectories: true)
        try "binario".write(to: weirdFolder.appendingPathComponent("datos.bin"), atomically: true, encoding: .utf8)

        let index = SearchIndex(databaseURL: tempDir.appendingPathComponent("index.sqlite"))
        _ = try await index.addRoot(path: rootURL.path)

        let coordinator = FilingCoordinator(
            index: index,
            rootURL: rootURL,
            knowledge: LocalKnowledgeStore(fileURL: tempDir.appendingPathComponent("knowledge.json"))
        )
        let outcome = await coordinator.processItem(at: weirdFolder)

        // Sin reglas para «.bin» ni para el nombre → cuarentena, pero la carpeta viaja entera.
        XCTAssertEqual(outcome.action, "quarantine")
        XCTAssertEqual(outcome.categoryPath, "99_SinClasificar")
        XCTAssertFalse(FileManager.default.fileExists(atPath: weirdFolder.path))
        let destination = URL(fileURLWithPath: outcome.destinationPath)
        XCTAssertEqual(destination.lastPathComponent, "Paquete Raro")
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("datos.bin").path))

        let journal = try await index.journalRecent(limit: 10)
        XCTAssertEqual(journal.first?.action, "quarantine")
    }

    func testFolderClassificationIgnoresInnerTextNoise() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("j4i-folder-noise-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let rootURL = tempDir.appendingPathComponent("organizado", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        // Cajón de sastre con un documento que menciona «factura»/«nómina»: el texto de un documento
        // suelto NO debe decidir por toda la carpeta → cuarentena (revisable), no Fiscal/Nominas.
        XCTAssertNil(RulesFilingClassifier.classifyFolder(name: "Carpeta de Papeles", dominantExtension: "txt"))

        let bucket = tempDir.appendingPathComponent("entrada", isDirectory: true)
            .appendingPathComponent("Carpeta de Papeles", isDirectory: true)
        try FileManager.default.createDirectory(at: bucket, withIntermediateDirectories: true)
        try "factura de luz y nómina del mes".write(to: bucket.appendingPathComponent("notas.txt"), atomically: true, encoding: .utf8)

        let index = SearchIndex(databaseURL: tempDir.appendingPathComponent("index.sqlite"))
        _ = try await index.addRoot(path: rootURL.path)

        let coordinator = FilingCoordinator(
            index: index,
            rootURL: rootURL,
            knowledge: LocalKnowledgeStore(fileURL: tempDir.appendingPathComponent("knowledge.json"))
        )
        let outcome = await coordinator.processItem(at: bucket)
        XCTAssertEqual(outcome.action, "quarantine")
        XCTAssertEqual(outcome.categoryPath, "99_SinClasificar")
    }

    func testFolderProfilerPrefersVideoOnTie() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("j4i-profiler-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Cuenta empatada (1 mkv + 1 m4a + 1 jpg + 1 txt): gana la familia de vídeo.
        for name in ["video.mkv", "audio.m4a", "foto.jpg", "notas.txt"] {
            try "x".write(to: tempDir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        let summary = FolderProfiler.summarize(folderURL: tempDir)
        XCTAssertEqual(summary.dominantExtension, "mkv")
        XCTAssertEqual(
            RulesFilingClassifier.classifyFolder(name: "Video Suelto", dominantExtension: summary.dominantExtension)?.categoryPath,
            "13_Multimedia/Videos"
        )
    }

    func testShellFolderWithoutFilesIsLeftInOriginNotQuarantined() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("j4i-folder-shell-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let rootURL = tempDir.appendingPathComponent("organizado", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        // Cáscara estilo «AnyUkit»: 0 ficheros, solo subcarpetas vacías (los enlaces de carpeta
        // apuntan a directorios que ya se vaciaron; no hay nada que archivar).
        let sourceDir = tempDir.appendingPathComponent("entrada", isDirectory: true)
        let shell = sourceDir.appendingPathComponent("AnyUkit", isDirectory: true)
        try FileManager.default.createDirectory(at: shell.appendingPathComponent("music"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: shell.appendingPathComponent("video"), withIntermediateDirectories: true)

        let index = SearchIndex(databaseURL: tempDir.appendingPathComponent("index.sqlite"))
        _ = try await index.addRoot(path: rootURL.path)

        let coordinator = FilingCoordinator(
            index: index,
            rootURL: rootURL,
            knowledge: LocalKnowledgeStore(fileURL: tempDir.appendingPathComponent("knowledge.json"))
        )
        let outcome = await coordinator.processItem(at: shell)

        XCTAssertEqual(outcome.action, "skipped-empty")
        XCTAssertTrue(FileManager.default.fileExists(atPath: shell.path), "la cáscara se queda en origen")
        XCTAssertFalse(FileManager.default.fileExists(atPath: rootURL.appendingPathComponent("99_SinClasificar/AnyUkit").path))
    }
}
