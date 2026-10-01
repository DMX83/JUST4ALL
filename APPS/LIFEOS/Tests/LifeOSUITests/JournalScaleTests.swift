import SwiftUI
import XCTest
@testable import LifeOSUI

/// La escala del ánimo y la energía: **de rojo a verde**, con cinco escalones, y con
/// palabras que son las mismas que las de la web.
///
/// Se prueban los **datos** de la escala (sus colores en claro y en oscuro, tal cual se
/// declaran) en vez del `Color` resuelto: un color dinámico depende de la apariencia del
/// sistema en ese momento, así que comprobarlo «resuelto» probaría otra cosa.
final class JournalScaleTests: XCTestCase {

    private struct RGB {
        let r: Double
        let g: Double
        let b: Double

        /// Cuánto de verde tiene, quitando el rojo: es lo que crece del 1 al 5.
        var greenness: Double { g - r }
    }

    private func rgb(_ hex: String) -> RGB {
        var value: UInt64 = 0
        Scanner(string: hex.hasPrefix("#") ? String(hex.dropFirst()) : hex).scanHexInt64(&value)
        return RGB(
            r: Double((value & 0xFF0000) >> 16) / 255,
            g: Double((value & 0x00FF00) >> 8) / 255,
            b: Double(value & 0x0000FF) / 255
        )
    }

    private var variants: [(name: String, hex: (JournalScale.Step) -> String)] {
        [("claro", { $0.light }), ("oscuro", { $0.dark })]
    }

    // MARK: - Forma de la escala

    func testTieneCincoEscalonesEnOrden() {
        XCTAssertEqual(JournalScale.steps.count, 5)
        XCTAssertEqual(JournalScale.levels, [1, 2, 3, 4, 5])
    }

    /// Fuera de rango se recorta: un servidor que mande un 7 (o un 0) no debe romper la vista.
    func testFueraDeRangoSeRecortaaLosExtremos() {
        XCTAssertEqual(JournalScale.stepIndex(for: 1), 0)
        XCTAssertEqual(JournalScale.stepIndex(for: 5), 4)
        XCTAssertEqual(JournalScale.stepIndex(for: 0), 0)
        XCTAssertEqual(JournalScale.stepIndex(for: -3), 0)
        XCTAssertEqual(JournalScale.stepIndex(for: 7), 4)
    }

    // MARK: - Rojo a verde

    func testVaDeRojoAVerdeEnClaroYEnOscuro() {
        for variant in variants {
            let tones = JournalScale.steps.map { rgb(variant.hex($0)) }
            XCTAssertGreaterThan(tones[0].r, tones[0].g, "el nivel 1 debe ser rojo (\(variant.name))")
            XCTAssertGreaterThan(tones[4].g, tones[4].r, "el nivel 5 debe ser verde (\(variant.name))")
        }
    }

    /// Y sin vuelta atrás: cada escalón tiene que ser **más verde** que el anterior
    /// (si no, el usuario ve un salto raro al subir de nivel).
    func testCadaEscalonEsMasVerdeQueElAnterior() {
        for variant in variants {
            let tones = JournalScale.steps.map { rgb(variant.hex($0)) }
            for index in 1..<tones.count {
                XCTAssertGreaterThan(
                    tones[index].greenness,
                    tones[index - 1].greenness,
                    "el escalón \(index + 1) tiene que ser más verde que el \(index) (\(variant.name))"
                )
            }
        }
    }

    /// Cinco colores distintos: dos niveles iguales harían ilegible la escala.
    func testLosCincoTonosSonDistintos() {
        for variant in variants {
            let hexes = JournalScale.steps.map { variant.hex($0) }
            XCTAssertEqual(Set(hexes).count, 5, "hay tonos repetidos (\(variant.name))")
        }
    }

    /// Cada tono tiene su versión clara y su versión oscura: si fueran iguales, la escala
    /// se comería algún fondo.
    func testCadaTonoSeAdaptaAlTema() {
        for step in JournalScale.steps {
            XCTAssertNotEqual(step.light, step.dark)
        }
    }

    // MARK: - Palabras

    /// Las palabras son **las de la web** (`web/components/journal-view.tsx`): app y web
    /// tienen que decir lo mismo del mismo día.
    func testLasPalabrasSonLasDeLaWeb() {
        XCTAssertEqual(
            JournalScale.levels.map { JournalScale.label(.mood, for: $0) },
            ["Muy bajo", "Bajo", "Neutro", "Bien", "Muy bien"]
        )
        XCTAssertEqual(
            JournalScale.levels.map { JournalScale.label(.energy, for: $0) },
            ["Sin energía", "Baja", "Media", "Alta", "Mucha"]
        )
    }

    /// El texto hablado lleva palabra **y** número: es el canal que no depende del color.
    func testElTextoHabladoLlevaPalabraYNumero() {
        XCTAssertEqual(JournalScale.spoken(.mood, for: 4), "Ánimo 4 de 5: Bien")
        XCTAssertEqual(JournalScale.spoken(.energy, for: 1), "Energía 1 de 5: Sin energía")
    }

    /// Un nivel imposible no debe producir una etiqueta vacía ni un índice fuera del array.
    func testUnNivelImposibleNoRevienta() {
        XCTAssertEqual(JournalScale.label(.mood, for: 9), "9 de 5")
        XCTAssertEqual(JournalScale.label(.energy, for: 0), "0 de 5")
        XCTAssertFalse(JournalScale.spoken(.mood, for: 9).isEmpty)
    }
}
