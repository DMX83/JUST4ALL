import XCTest
import J4IDocs
import J4ICore
@testable import J4IAI

final class DeepSeekAdvisorTests: XCTestCase {
    func testProposalParsingFromModelContent() throws {
        let content = "Aquí va el json: {\"category_path\": \"01_Fiscal/Facturas\", \"suggested_filename\": \"Factura-Luz-Marzo\", \"confidence\": 0.87, \"reason\": \"importe y emisor\", \"issuer\": \"Iberdrola\", \"document_date\": \"2026-03-12\"}"
        let proposal = try DeepSeekFilingAdvisor.proposal(fromContent: content)
        XCTAssertEqual(proposal.categoryPath, "01_Fiscal/Facturas")
        XCTAssertEqual(proposal.suggestedTitle, "Factura-Luz-Marzo")
        XCTAssertEqual(proposal.confidence, 0.87)
        XCTAssertEqual(proposal.source, .ai)
        XCTAssertEqual(proposal.documentDate, "2026-03-12")
        XCTAssertEqual(proposal.issuer, "Iberdrola")
    }

    func testProposalParsingFailsWithoutJSON() {
        XCTAssertThrowsError(try DeepSeekFilingAdvisor.proposal(fromContent: "sin objeto aquí"))
    }

    func testProposalParsingClampsConfidence() throws {
        let content = "{\"category_path\": \"01_Fiscal/Facturas\", \"confidence\": 1.7}"
        let proposal = try DeepSeekFilingAdvisor.proposal(fromContent: content)
        XCTAssertEqual(proposal.confidence, 1.0)
    }

    func testProposalParsesFolderSplitMode() throws {
        let content = "{\"category_path\": \"99_SinClasificar\", \"confidence\": 0.8, \"reason\": \"cajón heterogéneo\", \"mode\": \"split\"}"
        let proposal = try DeepSeekFilingAdvisor.proposal(fromContent: content)
        XCTAssertEqual(proposal.folderStrategy, .split)
    }

    func testProposalWithoutModeDefaultsToWholeFolder() throws {
        let content = "{\"category_path\": \"13_Multimedia/Videos\", \"confidence\": 0.9, \"reason\": \"carpeta coherente\"}"
        let proposal = try DeepSeekFilingAdvisor.proposal(fromContent: content)
        XCTAssertNil(proposal.folderStrategy, "sin mode, la carpeta va entera (por defecto)")
    }

    func testUserPromptIncludesCategoriesAndTruncatesSample() {
        var sample = String(repeating: "a", count: 10_000)
        sample += "final-secreto"
        let profile = DocumentProfile(
            fileName: "doc.pdf",
            fileExtension: "pdf",
            fileSizeBytes: 10,
            contentHash: "hash",
            hasTextLayer: true,
            usedOCR: false,
            pageCount: 1,
            textLength: sample.count,
            textSample: sample,
            dates: [],
            amounts: [],
            identifiers: [],
            analyzedAt: Date()
        )
        let prompt = DeepSeekFilingAdvisor.userPrompt(
            profile: profile,
            allowedCategories: ["01_Fiscal/Facturas", "99_SinClasificar"]
        )
        XCTAssertTrue(prompt.contains("01_Fiscal/Facturas"))
        XCTAssertFalse(prompt.contains("final-secreto"), "la muestra debe ir truncada")
    }

    func testKeyResolverReadsEnvSecretsFile() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("j4i-secrets-\(UUID().uuidString)", isDirectory: true)
        let nested = folder.appendingPathComponent("a/b", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try "# comentario\nDEEPSEEK_API_KEY='sk-test-123'\n".write(
            to: folder.appendingPathComponent(".env.secrets"),
            atomically: true,
            encoding: .utf8
        )

        let key = DeepSeekKeyResolver.resolve(environment: [:], startingAt: nested)
        XCTAssertEqual(key, "sk-test-123")
    }

    func testKeyResolverPrefersEnvironment() {
        let key = DeepSeekKeyResolver.resolve(environment: ["DEEPSEEK_API_KEY": "sk-env"], startingAt: URL(fileURLWithPath: "/"))
        XCTAssertEqual(key, "sk-env")
    }
}
