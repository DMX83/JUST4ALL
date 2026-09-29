import XCTest
import AppKit
@testable import J4FUI

/// v2.3.14 — Regresión de la incidencia «presiono Return/Enter y no hace nada».
///
/// Causa: los atajos sin modificadores (Return, Espacio, Tab, F5–F8, filtro rápido) exigían
/// `flags == []`, pero macOS añade modificadores «de ruido» según el teclado y el estado del
/// sistema: `.numericPad` en el Enter del teclado numérico (que es lo que manda la tecla grande
/// «Enter» de muchos teclados estilo Windows), `.function` en F1–F12 y flechas, y `.capsLock`
/// cuando el Bloqueo de mayúsculas está activo.
final class KeyNavigationFlagsTests: XCTestCase {

    /// Return «limpio»: nada que filtrar.
    func testPlainReturnHasNoSignificantModifiers() {
        XCTAssertTrue(KeyNavigationFlags.significant([]).isEmpty)
    }

    /// Tecla «Enter» de teclado estilo Windows (keyCode 76 + numericPad) ⇒ debe contar como Return.
    func testNumericPadEnterIsTreatedAsPlainKey() {
        XCTAssertTrue(KeyNavigationFlags.significant([.numericPad]).isEmpty)
    }

    /// F1–F12 y flechas llegan con `.function` (la tecla fn del Mac): no deben bloquear el atajo.
    func testFunctionFlagIsIgnored() {
        XCTAssertTrue(KeyNavigationFlags.significant([.function]).isEmpty)
    }

    /// Bloqueo de mayúsculas activo: no debe desactivar Return/Espacio/Tab/filtro rápido.
    func testCapsLockIsIgnored() {
        XCTAssertTrue(KeyNavigationFlags.significant([.capsLock]).isEmpty)
    }

    /// Combinación real de un teclado externo con Bloqueo de mayúsculas: sigue siendo «sin modificadores».
    func testNumericPadPlusCapsLockPlusFunctionIsStillPlain() {
        XCTAssertTrue(KeyNavigationFlags.significant([.numericPad, .capsLock, .function]).isEmpty)
    }

    /// Los modificadores que el usuario sí pulsa se conservan (los atajos ⌘/⌥/⇧/⌃ deben seguir
    /// resolviéndose y no caer en la rama «sin modificadores»).
    func testRealModifiersArePreserved() {
        XCTAssertEqual(KeyNavigationFlags.significant([.command]), [.command])
        XCTAssertEqual(KeyNavigationFlags.significant([.shift]), [.shift])
        XCTAssertEqual(KeyNavigationFlags.significant([.option]), [.option])
        XCTAssertEqual(KeyNavigationFlags.significant([.control]), [.control])
    }

    /// Y se conservan aunque vengan acompañados de ruido (⌘ + Bloqueo de mayúsculas ⇒ ⌘T sigue siendo ⌘T).
    func testRealModifiersSurviveNoiseFlags() {
        XCTAssertEqual(KeyNavigationFlags.significant([.command, .capsLock, .numericPad]), [.command])
    }

    /// Ruido puro + modificador real ⇒ nunca se confunde con «sin modificadores».
    func testNoiseAloneNeverLooksLikeACommand() {
        let significant = KeyNavigationFlags.significant([.numericPad, .function])
        XCTAssertFalse(significant.contains(.command))
        XCTAssertTrue(significant.isEmpty)
    }
}
