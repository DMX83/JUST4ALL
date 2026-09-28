import XCTest
@testable import JUST4DESK

/// N5 — texto del aviso del sistema ««X» → «Y»» (se prueba el formato sin tocar el centro
/// de notificaciones, que no existe en ejecución de tests sin bundle).
final class FilingNotifierTests: XCTestCase {
    func testBodyFormat() {
        XCTAssertEqual(
            FilingNotifier.body(name: "recibo.pdf", category: "01_Fiscal/Facturas"),
            "«recibo.pdf» → «01_Fiscal/Facturas»"
        )
    }

    func testDefaultIsEnabled() {
        // Sin clave guardada, el interruptor nace activado (la clave la escribe solo Ajustes).
        UserDefaults.standard.removeObject(forKey: FilingNotifier.defaultsKey)
        XCTAssertTrue(FilingNotifier.shared.isEnabled)
    }
}
