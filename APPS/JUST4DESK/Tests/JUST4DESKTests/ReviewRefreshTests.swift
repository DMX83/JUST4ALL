import XCTest
import J4ICore
@testable import JUST4DESK

/// Auto-actualización de «Por revisar»: los ficheros borrados fuera de la app (Finder) se quitan
/// de la lista sin errores, y lo nuevo aparece sin reabrir la ventana; el estado (selección y
/// destinos elegidos) se conserva.
final class ReviewRefreshTests: XCTestCase {
    private var tempRoot: URL!
    private var savedRoot: String?
    private var quarantine: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("j4d-review-\(UUID().uuidString)", isDirectory: true)
        quarantine = tempRoot.appendingPathComponent(DefaultTaxonomy.quarantineRelativePath, isDirectory: true)
        try FileManager.default.createDirectory(at: quarantine, withIntermediateDirectories: true)
        savedRoot = FilingConfiguration.rootPath
        FilingConfiguration.rootPath = tempRoot.path
    }

    override func tearDownWithError() throws {
        FilingConfiguration.rootPath = savedRoot
        try? FileManager.default.removeItem(at: tempRoot)
    }

    private func write(_ name: String) throws -> URL {
        let url = quarantine.appendingPathComponent(name)
        try "contenido".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @MainActor
    func testRefreshDropsFilesDeletedOutsideTheApp() throws {
        _ = try write("se-queda.txt")
        let gone = try write("borrado-fuera.txt")

        let model = ReviewViewModel()
        model.load()
        XCTAssertEqual(model.items.count, 2)
        // Los ids reales del modelo (las rutas pueden venir canonizadas como /private/var…).
        let keepID = try XCTUnwrap(model.items.first { $0.name == "se-queda.txt" }?.id)
        let goneID = try XCTUnwrap(model.items.first { $0.name == "borrado-fuera.txt" }?.id)
        model.selection = [keepID, goneID]

        try FileManager.default.removeItem(at: gone) // borrado «desde el Finder»
        let vanished = model.refreshFromDisk()

        XCTAssertEqual(vanished, 1, "debe detectar el borrado externo")
        XCTAssertEqual(model.items.map(\.name), ["se-queda.txt"], "el fichero borrado desaparece de la lista")
        XCTAssertEqual(model.selection, [keepID], "la selección pierde lo desaparecido")
    }

    @MainActor
    func testRefreshKeepsChosenDestinationAndAddsNewFiles() throws {
        _ = try write("uno.pdf")
        let model = ReviewViewModel()
        model.load()
        let unoID = try XCTUnwrap(model.items.first { $0.name == "uno.pdf" }?.id)
        model.setDestination("01_Fiscal/Facturas", for: unoID)

        _ = try write("dos.pdf") // llega mientras la ventana está abierta
        let vanished = model.refreshFromDisk()

        XCTAssertEqual(vanished, 0)
        XCTAssertEqual(model.items.count, 2, "lo nuevo aparece sin reabrir la ventana")
        XCTAssertEqual(
            model.items.first { $0.name == "uno.pdf" }?.destination,
            "01_Fiscal/Facturas",
            "el destino elegido a mano se conserva al refrescar"
        )
        XCTAssertEqual(
            model.items.first { $0.name == "dos.pdf" }?.destination,
            nil,
            "lo nuevo llega sin destino preseleccionado si no hay regla (pdf sin palabra clave)"
        )
    }

    @MainActor
    func testRefreshOnEmptyQuarantineClearsList() throws {
        let gone = try write("temporal.txt")
        let model = ReviewViewModel()
        model.load()
        XCTAssertEqual(model.items.count, 1)

        try FileManager.default.removeItem(at: gone)
        XCTAssertEqual(model.refreshFromDisk(), 1)
        XCTAssertTrue(model.items.isEmpty)
    }
}
