import XCTest
import J4ICore
import J4IIndex
@testable import J4IFiling

/// F10.0 — Desglose de carpetas-cajón («la IA decide entera o por ficheros»).
/// Aquí se prueba el desglose MANUAL (sin IA): cada hijo se clasifica por separado con las reglas
/// locales, todo comparte un mismo lote de undo y la cáscara vacía queda en origen.
final class FolderSplitTests: XCTestCase {
    func testSplitFolderArchivesChildrenIndividuallyAndKeepsShell() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("j4i-split-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let rootURL = tempDir.appendingPathComponent("organizado", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let sourceDir = tempDir.appendingPathComponent("entrada", isDirectory: true)
        let bucket = sourceDir.appendingPathComponent("Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: bucket, withIntermediateDirectories: true)
        try "Factura de luz marzo".write(to: bucket.appendingPathComponent("Factura-Luz-Marzo.txt"), atomically: true, encoding: .utf8)
        try "binario".write(to: bucket.appendingPathComponent("datos.bin"), atomically: true, encoding: .utf8)

        let index = SearchIndex(databaseURL: tempDir.appendingPathComponent("index.sqlite"))
        _ = try await index.addRoot(path: rootURL.path)

        let coordinator = FilingCoordinator(
            index: index,
            rootURL: rootURL,
            knowledge: LocalKnowledgeStore(fileURL: tempDir.appendingPathComponent("knowledge.json"))
        )
        let outcome = await coordinator.splitFolder(at: bucket)

        XCTAssertEqual(outcome.action, "split")
        // El fichero clasificable se archiva por su cuenta…
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: rootURL.appendingPathComponent("01_Fiscal/Facturas/Factura-Luz-Marzo.txt").path),
            "el fichero con señal debe archivarse individualmente"
        )
        // …y el que no tiene señal va a la carpeta «sin clasificar» POR SEPARADO (no arrastra a la carpeta).
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: rootURL.appendingPathComponent("99_SinClasificar/datos.bin").path),
            "el fichero sin señal debe ir a «sin clasificar» individual"
        )
        // La cáscara vacía queda en origen (nunca se borra) y ya no contiene elementos.
        XCTAssertTrue(FileManager.default.fileExists(atPath: bucket.path), "la cáscara se queda en origen")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: bucket.path)
        XCTAssertTrue(leftovers.isEmpty, "la cáscara debe quedar vacía")

        // Los dos movimientos comparten lote (deshacer en conjunto desde Actividad).
        let journal = try await index.journalRecent(limit: 10)
        XCTAssertEqual(journal.count, 2)
        XCTAssertEqual(Set(journal.map(\.batchID)).count, 1, "el desglose va en un único lote de undo")
    }
}
