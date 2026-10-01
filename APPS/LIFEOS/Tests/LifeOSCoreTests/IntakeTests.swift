import XCTest

import LifeOSAPI
import LifeOSCore

/// Lo que entra desde fuera de la app: qué se acepta, qué no, y **por qué**.
///
/// Estas reglas son las del servidor (`20 MB`, cuatro extensiones, 10 000
/// caracteres por anotación). Se comprueban aquí, sin red, porque el objetivo de
/// `EvidenceIntake` es justamente ese: que el usuario reciba una frase que
/// entienda en vez de un 422 seco.
final class IntakeTests: XCTestCase {
    private let pdf = URL(fileURLWithPath: "/tmp/informe.pdf")

    // MARK: - Texto

    func testNormalTextBecomesACapture() {
        XCTAssertEqual(
            EvidenceIntake.plan(for: .text("  Llamar a la gestoría mañana  ")),
            .capture(text: "Llamar a la gestoría mañana")
        )
    }

    func testEmptyTextIsRefusedInsteadOfSent() {
        for raw in ["", "   ", "\n\t "] {
            guard case .refuse(let reason, _) = EvidenceIntake.plan(for: .text(raw)) else {
                return XCTFail("«\(raw)» debería rechazarse")
            }
            XCTAssertTrue(reason.contains("nada que enviar"), reason)
        }
    }

    /// El servidor corta en 10 000 (`CaptureCreate.content`). Mandarlo y comerse
    /// el 422 sería lo fácil; decirlo es lo útil.
    func testLongTextIsRefusedWithTheRealLimit() {
        let long = String(repeating: "a", count: EvidenceIntake.maxCaptureCharacters + 1)

        guard case .refuse(let reason, let note) = EvidenceIntake.plan(for: .text(long)) else {
            return XCTFail("Debería rechazarse")
        }
        XCTAssertTrue(reason.contains("10001"), reason)
        XCTAssertTrue(reason.contains("10000"), reason)
        XCTAssertNil(note, "Un texto largo no se puede «anotar como nota»: no cabría")
    }

    func testTextRightAtTheLimitIsAccepted() {
        let justo = String(repeating: "a", count: EvidenceIntake.maxCaptureCharacters)
        XCTAssertEqual(EvidenceIntake.plan(for: .text(justo)), .capture(text: justo))
    }

    // MARK: - Ficheros

    func testSupportedFilesGoToDocumentsWithTheirMimeType() {
        let cases: [(String, String)] = [
            ("informe.pdf", "application/pdf"),
            ("notas.docx", "application/vnd.openxmlformats-officedocument.wordprocessingml.document"),
            ("apuntes.md", "text/plain"),
            ("carta.txt", "text/plain")
        ]
        for (name, mime) in cases {
            let url = URL(fileURLWithPath: "/tmp/\(name)")
            guard case .upload(_, let filename, let mimeType) = EvidenceIntake.plan(
                for: .file(url, size: 1_024)
            ) else {
                return XCTFail("«\(name)» debería subirse")
            }
            XCTAssertEqual(filename, name)
            XCTAssertEqual(mimeType, mime)
        }
    }

    func testExtensionIsMatchedHoweverItIsWritten() {
        // El servidor compara la extensión en minúsculas; «FOTO.PDF» también vale.
        let url = URL(fileURLWithPath: "/tmp/INFORME.PDF")
        guard case .upload = EvidenceIntake.plan(for: .file(url, size: 10)) else {
            return XCTFail("La extensión debería compararse sin distinguir mayúsculas")
        }
    }

    func testUnsupportedFileIsRefusedAndOffersThePathAsANote() {
        let foto = URL(fileURLWithPath: "/tmp/foto.jpg")

        guard case .refuse(let reason, let note) = EvidenceIntake.plan(for: .file(foto, size: 2_048)) else {
            return XCTFail("Una foto no se puede subir como documento")
        }
        XCTAssertTrue(reason.contains("foto.jpg"), reason)
        XCTAssertTrue(reason.contains("PDF"), reason)
        XCTAssertEqual(note, "/tmp/foto.jpg", "Se ofrece la ruta para no perder el rastro")
    }

    func testHugeFileIsRefusedWithBothSizes() {
        let url = URL(fileURLWithPath: "/tmp/enorme.pdf")
        let veintiuno = EvidenceIntake.maxDocumentBytes + 1

        guard case .refuse(let reason, _) = EvidenceIntake.plan(for: .file(url, size: veintiuno)) else {
            return XCTFail("Debería rechazarse por tamaño")
        }
        XCTAssertTrue(reason.contains("máximo"), reason)
        XCTAssertTrue(reason.contains("20 MB"), reason)
        // Un byte por encima no puede salir como «pesa 21 MB y el máximo son 21 MB»:
        // con el redondeo empatado, se dice solo que se pasa.
        XCTAssertFalse(reason.contains("21 MB y el máximo son 21 MB"), reason)
    }

    func testHugeFileFarOverTheLimitSaysHowMuchItWeighs() {
        let url = URL(fileURLWithPath: "/tmp/video.pdf")

        guard case .refuse(let reason, _) = EvidenceIntake.plan(
            for: .file(url, size: 40 * 1024 * 1024)
        ) else {
            return XCTFail("Debería rechazarse por tamaño")
        }
        XCTAssertTrue(reason.contains("40 MB"), reason)
        XCTAssertTrue(reason.contains("20 MB"), reason)
    }

    func testEmptyFileIsRefused() {
        guard case .refuse(let reason, let note) = EvidenceIntake.plan(for: .file(pdf, size: 0)) else {
            return XCTFail("Un fichero vacío no se puede procesar")
        }
        XCTAssertTrue(reason.contains("vacío"), reason)
        XCTAssertNil(note, "Un fichero vacío no merece ni una nota")
    }

    func testUnknownSizeIsNotAWayToReject() {
        // Si no se pudo medir, se intenta: el servidor es quien decide.
        guard case .upload = EvidenceIntake.plan(for: .file(pdf, size: nil)) else {
            return XCTFail("Sin tamaño conocido debería intentarse")
        }
    }

    func testWebURLIsRefusedBecauseItIsNotAFile() {
        let web = URL(string: "https://perlatec.net/nota")!
        guard case .refuse(let reason, _) = EvidenceIntake.plan(for: .file(web, size: nil)) else {
            return XCTFail("Un enlace no es un fichero")
        }
        XCTAssertTrue(reason.contains("no es un fichero del Mac"), reason)
    }

    // MARK: - Nombre del documento

    func testDocumentTitleDropsTheExtension() {
        XCTAssertEqual(
            EvidenceIntake.title(for: URL(fileURLWithPath: "/tmp/Factura luz 2026.pdf")),
            "Factura luz 2026"
        )
    }

    /// El límite de extensiones tiene que ser el del servidor: si aquí se colara
    /// una de más, el fallo aparecería al subir.
    func testAllowedExtensionsAreTheOnesTheServerUnderstands() {
        XCTAssertEqual(EvidenceIntake.allowedExtensions, ["pdf", "docx", "txt", "md"])
    }
}
