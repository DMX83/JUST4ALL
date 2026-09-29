import XCTest
import AppKit
@testable import J4FUI

/// v2.3.15 — Contrato de teclas del commander. Regresión del malentendido real: el usuario pidió
/// «Return para volver» cuando la tecla que usaba era **Retroceso (⌫)**; y en teclados estilo
/// Windows la tecla grande «Enter» llega a macOS como el Enter del teclado numérico (76).
final class KeyNavigationKeysTests: XCTestCase {

    /// Return (36) y Enter del teclado numérico (76) ABREN la selección (entrar en la carpeta).
    func testReturnAndNumericPadEnterOpenTheSelection() {
        XCTAssertTrue(KeyNavigationKeys.opensSelection(36))
        XCTAssertTrue(KeyNavigationKeys.opensSelection(76))
        XCTAssertEqual(KeyNavigationKeys.openSelection, [36, 76])
    }

    /// Retroceso ⌫ (51) VUELVE a la ubicación anterior.
    func testBackspaceGoesBack() {
        XCTAssertTrue(KeyNavigationKeys.goesBack(51))
        XCTAssertEqual(KeyNavigationKeys.goBack, [51])
    }

    /// Y no se pisan: 51 no abre y 36/76 no vuelven (era el error de interpretación original).
    func testOpenAndBackAreDisjoint() {
        XCTAssertTrue(KeyNavigationKeys.openSelection.isDisjoint(with: KeyNavigationKeys.goBack))
        XCTAssertFalse(KeyNavigationKeys.opensSelection(51))
        XCTAssertFalse(KeyNavigationKeys.goesBack(36))
        XCTAssertFalse(KeyNavigationKeys.goesBack(76))
    }

    /// Teclas vecinas que NO deben confundirse con Return/Retroceso: Tab (48), Esc (53),
    /// flechas (123-126) y Borrar-adelante (117).
    func testNeighbouringKeysAreUnmapped() {
        for keyCode: UInt16 in [48, 53, 117, 123, 124, 125, 126] {
            XCTAssertFalse(KeyNavigationKeys.opensSelection(keyCode), "keyCode \(keyCode) no debe abrir")
            XCTAssertFalse(KeyNavigationKeys.goesBack(keyCode), "keyCode \(keyCode) no debe volver")
        }
    }
}
