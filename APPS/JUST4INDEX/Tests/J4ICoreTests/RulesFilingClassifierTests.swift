import XCTest
@testable import J4ICore

final class RulesFilingClassifierTests: XCTestCase {
    func testNameRulesHandleSoftwareNames() {
        let proposal = RulesFilingClassifier.classify(fileName: "dotnet-sdk-6.0.100-win-x64.exe", textSample: "")
        XCTAssertEqual(proposal?.categoryPath, "12_Software/Desarrollo")
        XCTAssertEqual(proposal?.source, .rules)
    }

    func testExtensionFallbackMapsMediaArchivesAndInstallers() {
        XCTAssertEqual(RulesFilingClassifier.classifyByExtension(fileName: "video-final.mp4")?.categoryPath, "13_Multimedia/Videos")
        XCTAssertEqual(RulesFilingClassifier.classifyByExtension(fileName: "foto.jpg")?.categoryPath, "13_Multimedia/Fotos")
        XCTAssertEqual(RulesFilingClassifier.classifyByExtension(fileName: "pack.rar")?.categoryPath, "14_Comprimidos")
        XCTAssertEqual(RulesFilingClassifier.classifyByExtension(fileName: "setup.msi")?.categoryPath, "12_Software/Instaladores")
        XCTAssertNil(RulesFilingClassifier.classifyByExtension(fileName: "notas.txt"))
        XCTAssertNil(RulesFilingClassifier.classifyByExtension(fileName: "sin-extension"))
    }

    func testExtensionFallbackMapsTechnicalScriptsAndConfigs() {
        // F9.4: scripts de red y configuraciones de dispositivo → Redes; código → Desarrollo.
        XCTAssertEqual(RulesFilingClassifier.classifyByExtension(fileName: "222.rsc")?.categoryPath, "12_Software/Redes")
        XCTAssertEqual(RulesFilingClassifier.classifyByExtension(fileName: "cliente-vpn.ovpn")?.categoryPath, "12_Software/Redes")
        XCTAssertEqual(RulesFilingClassifier.classifyByExtension(fileName: "router-2026.backup")?.categoryPath, "12_Software/Redes")
        XCTAssertEqual(RulesFilingClassifier.classifyByExtension(fileName: "deploy-prod.py")?.categoryPath, "12_Software/Desarrollo")
        XCTAssertEqual(RulesFilingClassifier.classifyByExtension(fileName: "migracion.sql")?.categoryPath, "12_Software/Desarrollo")
        // El nombre sigue ganando a la extensión: «setup» manda a Instaladores incluso siendo .ps1.
        XCTAssertEqual(RulesFilingClassifier.suggestDestination(fileName: "setup-agente.ps1")?.categoryPath, "12_Software/Instaladores")
        // Carpeta-unidad: «scripts» + extensión dominante .rsc → Redes.
        XCTAssertEqual(RulesFilingClassifier.classifyFolder(name: "Scripts MikroTik", dominantExtension: "rsc")?.categoryPath, "12_Software/Redes")
    }

    func testNameRulesWinBeforeExtensionFallback() {
        // Un instalador de trading: el nombre («ctrader») debe pesar más que la extensión (.exe).
        let byName = RulesFilingClassifier.classify(fileName: "ctrader-litefinance-setup.exe", textSample: "")
        XCTAssertEqual(byName?.categoryPath, "02_Banca/Inversiones")
        XCTAssertEqual(RulesFilingClassifier.classifyByExtension(fileName: "ctrader-litefinance-setup.exe")?.categoryPath, "12_Software/Instaladores")
    }

    func testContentRulesStillBeatExtensionFallback() {
        // Una foto escaneada de una factura: el texto manda (Fiscal), no la extensión (Fotos).
        let proposal = RulesFilingClassifier.classify(fileName: "escaneo-2026-03.jpg", textSample: "Factura nº 123 del 12/03/2026 por 85,00 €")
        XCTAssertEqual(proposal?.categoryPath, "01_Fiscal/Facturas")
    }

    func testReviewSuggestionUsesNameThenExtension() {
        // La cola de revisión sugiere destino con las reglas locales: nombre primero, extensión después.
        XCTAssertEqual(RulesFilingClassifier.suggestDestination(fileName: "BoseUpdaterInstaller_7.1.13.exe")?.categoryPath, "12_Software/Instaladores")
        XCTAssertEqual(RulesFilingClassifier.suggestDestination(fileName: "ctrader-setup.exe")?.categoryPath, "02_Banca/Inversiones")
        XCTAssertEqual(RulesFilingClassifier.suggestDestination(fileName: "vacaciones.mp4")?.categoryPath, "13_Multimedia/Videos")
        XCTAssertNil(RulesFilingClassifier.suggestDestination(fileName: "misterio.bin"))
    }

    func testFineTaxonomyRulesRouteMediaBooksAndCourses() {
        // F9.2: multimedia fina, libros y cursos tienen destinos propios.
        XCTAssertEqual(RulesFilingClassifier.classifyFolder(name: "Above Majestic Documental Completo", dominantExtension: "mkv")?.categoryPath, "13_Multimedia/Documentales")
        XCTAssertEqual(RulesFilingClassifier.classifyFolder(name: "Index of Series The Terminal List", dominantExtension: "mkv")?.categoryPath, "13_Multimedia/Series")
        XCTAssertEqual(RulesFilingClassifier.classify(fileName: "Pelicula Dune Parte Dos (2024).mkv", textSample: "")?.categoryPath, "13_Multimedia/Peliculas")
        XCTAssertEqual(RulesFilingClassifier.classify(fileName: "audiolibro habitos atomicos.mp3", textSample: "")?.categoryPath, "13_Multimedia/Audiolibros")
        XCTAssertEqual(RulesFilingClassifier.classify(fileName: "curso-de-flutter-clase-3.mp4", textSample: "")?.categoryPath, "06_Educacion/Cursos")
        XCTAssertEqual(RulesFilingClassifier.classifyByExtension(fileName: "el-quijote.epub")?.categoryPath, "15_Libros")
        // Un vídeo sin señal en el nombre sigue cayendo en Videos (catch-all) por extensión.
        XCTAssertEqual(RulesFilingClassifier.classifyFolder(name: "Vacaciones 2025", dominantExtension: "mp4")?.categoryPath, "13_Multimedia/Videos")
    }
}
