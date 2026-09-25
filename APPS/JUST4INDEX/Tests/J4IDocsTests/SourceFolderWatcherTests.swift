import XCTest
@testable import J4IDocs

final class SourceFolderWatcherTests: XCTestCase {
    func testWatcherEmitsExistingStableFile() async throws {
        if ProcessInfo.processInfo.environment["J4I_SKIP_FSEVENTS_TESTS"] == "1" {
            throw XCTSkip("Tests de FSEvents deshabilitados por entorno")
        }
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("j4i-watch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let fileURL = folder.appendingPathComponent("factura-test.txt")
        try "factura".write(to: fileURL, atomically: true, encoding: .utf8)

        let emitted = expectation(description: "fichero estable emitido")
        let watcher = SourceFolderWatcher(stabilityInterval: 0.5, minimumStableTicks: 2)
        defer { watcher.stop() }
        try watcher.start(folder: folder) { url in
            if url.lastPathComponent == "factura-test.txt" {
                emitted.fulfill()
            }
        }
        await fulfillment(of: [emitted], timeout: 15)
    }

    func testWatcherEmitsNewFileAfterStabilizing() async throws {
        if ProcessInfo.processInfo.environment["J4I_SKIP_FSEVENTS_TESTS"] == "1" {
            throw XCTSkip("Tests de FSEvents deshabilitados por entorno")
        }
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("j4i-watch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let emitted = expectation(description: "fichero nuevo emitido")
        let watcher = SourceFolderWatcher(stabilityInterval: 0.5, minimumStableTicks: 2)
        defer { watcher.stop() }
        try watcher.start(folder: folder) { url in
            if url.lastPathComponent == "nuevo-doc.txt" {
                emitted.fulfill()
            }
        }

        try? await Task.sleep(nanoseconds: 500_000_000)
        try "contenido".write(to: folder.appendingPathComponent("nuevo-doc.txt"), atomically: true, encoding: .utf8)

        await fulfillment(of: [emitted], timeout: 15)
    }

    func testWatcherEmitsExistingFolderAsUnit() async throws {
        if ProcessInfo.processInfo.environment["J4I_SKIP_FSEVENTS_TESTS"] == "1" {
            throw XCTSkip("Tests de FSEvents deshabilitados por entorno")
        }
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("j4i-watch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        // Las carpetas también son unidades: el backlog debe emitirlas (antes se descartaban).
        let subfolder = folder.appendingPathComponent("Documental Pendiente", isDirectory: true)
        try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)
        try "video".write(to: subfolder.appendingPathComponent("video.mp4"), atomically: true, encoding: .utf8)

        let emitted = expectation(description: "carpeta emitida como unidad")
        let watcher = SourceFolderWatcher(stabilityInterval: 0.5, minimumStableTicks: 2)
        defer { watcher.stop() }
        try watcher.start(folder: folder) { url in
            if url.lastPathComponent == "Documental Pendiente" {
                emitted.fulfill()
            }
        }
        await fulfillment(of: [emitted], timeout: 15)
    }
}
