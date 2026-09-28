import XCTest
@testable import JUST4PICT

@MainActor
final class InputQueueViewModelTests: XCTestCase {
    func testMergeFiltersUnsupportedAndDeduplicates() {
        let queue = InputQueueViewModel()

        let accepted = queue.merge([
            URL(fileURLWithPath: "/tmp/j4pict/a.jpg"),
            URL(fileURLWithPath: "/tmp/j4pict/a.jpg"),
            URL(fileURLWithPath: "/tmp/j4pict/b.txt"),
            URL(fileURLWithPath: "/tmp/j4pict/b.png")
        ])

        XCTAssertEqual(accepted, 3, "cuenta los normalizados (soportados), no los descartados")
        XCTAssertEqual(queue.files.count, 2, "la ruta duplicada estandarizada solo entra una vez")
        XCTAssertEqual(queue.files.map(\.lastPathComponent), ["a.jpg", "b.png"])
    }

    func testMergeKeepsShuffledOrderAndExtensionCaseInsensitive() {
        let queue = InputQueueViewModel()

        _ = queue.merge([
            URL(fileURLWithPath: "/tmp/j4pict/C.HEIC"),
            URL(fileURLWithPath: "/tmp/j4pict/d.webp")
        ])

        XCTAssertEqual(queue.files.map(\.lastPathComponent), ["C.HEIC", "d.webp"])
    }

    func testCollectImagesRecursesSkipsHiddenAndUnsupported() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sub = root.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Data().write(to: root.appendingPathComponent("uno.jpg"))
        try Data().write(to: sub.appendingPathComponent("dos.png"))
        try Data().write(to: sub.appendingPathComponent("notas.txt"))
        try Data().write(to: sub.appendingPathComponent(".oculto.jpg"))

        let queue = InputQueueViewModel()
        let urls = try queue.collectImages(in: root)

        XCTAssertEqual(urls.count, 2, "solo imágenes soportadas y visibles")
        XCTAssertTrue(urls.contains { $0.lastPathComponent == "uno.jpg" })
        XCTAssertTrue(urls.contains { $0.lastPathComponent == "dos.png" })
    }

    func testClearEmptiesFilesButKeepsOutputDirectory() {
        let queue = InputQueueViewModel()
        _ = queue.merge([URL(fileURLWithPath: "/tmp/j4pict/x.png")])
        queue.outputDirectory = URL(fileURLWithPath: "/tmp/salida")

        queue.clear()

        XCTAssertTrue(queue.files.isEmpty)
        XCTAssertNotNil(queue.outputDirectory, "la carpeta de salida es preferencia, no cola")
    }
}
