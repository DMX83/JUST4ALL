import SwiftUI
import XCTest
@testable import LifeOSUI

/// El orden de las secciones de la barra lateral y sus atajos.
///
/// El orden **es** el de `Pane.allCases`: de ahí salen la barra lateral y los ⌘1…⌘8. El
/// 30-sep-2026 el dueño pidió que el **Diario** fuera antes que la **Agenda**, y al moverlo
/// se renumeraron los atajos para que la barra se lea 1, 2, 3… de arriba abajo (sin saltos).
/// Estos dos hechos van juntos: si alguien vuelve a mover una sección, este test lo dice.
final class PaneOrderTests: XCTestCase {

    func testElOrdenDeLaBarraLateral() {
        XCTAssertEqual(
            MainView.Pane.allCases.map(\.title),
            ["Hoy", "Capturar", "Diario", "Agenda", "Ejecutar", "Buscar", "Bandeja", "Ajustes"]
        )
    }

    func testElDiarioVaAntesQueLaAgenda() throws {
        let titles = MainView.Pane.allCases.map(\.title)
        let journal = try XCTUnwrap(titles.firstIndex(of: "Diario"))
        let agenda = try XCTUnwrap(titles.firstIndex(of: "Agenda"))
        XCTAssertLessThan(journal, agenda, "el Diario tiene que ir antes que la Agenda")
    }

    /// Los atajos siguen el orden visual: ⌘1 el primero, ⌘8 el último.
    func testLosAtajosSiguenElOrden() {
        XCTAssertEqual(
            MainView.Pane.allCases.map { String($0.shortcut.character) },
            ["1", "2", "3", "4", "5", "6", "7", "8"]
        )
    }

    /// Cada sección tiene su icono: una celda sin símbolo se ve vacía en la barra.
    func testCadaSeccionTieneIcono() {
        for pane in MainView.Pane.allCases {
            XCTAssertFalse(pane.systemImage.isEmpty, "\(pane.title) se quedó sin icono")
        }
    }
}
