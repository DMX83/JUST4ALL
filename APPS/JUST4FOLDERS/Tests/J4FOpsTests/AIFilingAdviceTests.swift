import XCTest
@testable import J4FOps
import J4ICore

private struct StubAdvisor: FilingAdvising {
    let category: String
    let confidence: Double

    func propose(fileName: String, allowedCategories: [String]) async throws -> FilingProposal {
        FilingProposal(
            categoryPath: category,
            confidence: confidence,
            reason: "stub",
            source: .ai
        )
    }
}

private final class CountingAdvisor: FilingAdvising, @unchecked Sendable {
    let category: String
    let confidence: Double
    private(set) var calls = 0

    init(category: String, confidence: Double) {
        self.category = category
        self.confidence = confidence
    }

    func propose(fileName: String, allowedCategories: [String]) async throws -> FilingProposal {
        calls += 1
        return FilingProposal(categoryPath: category, confidence: confidence, reason: "stub", source: .ai)
    }
}

final class AIFilingAdviceTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("j4f-ai-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeFile(_ name: String) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try "x".data(using: .utf8)?.write(to: url)
        return url
    }

    func testPlanAsyncUsesAdvisorForQuarantineFiles() async throws {
        let file = try makeFile("asdf.qwerty")
        let baseline = FolderOrderer.plan(files: [file])
        XCTAssertTrue(baseline.first?.isQuarantine ?? false, "las reglas no lo saben clasificar")

        let advisor = StubAdvisor(category: "12_Software/Herramientas", confidence: 0.8)
        let refined = await FolderOrderer.planAsync(files: [file], advisor: advisor)

        XCTAssertEqual(refined.first?.destinationRelativePath, "12_Software/Herramientas")
        XCTAssertFalse(refined.first?.isQuarantine ?? true)
        XCTAssertEqual(refined.first?.reason.contains("IA") ?? false, true, "el motivo marca el origen IA")
    }

    func testPlanAsyncKeepsQuarantineWhenAIConfidenceIsLow() async throws {
        let file = try makeFile("asdf.qwerty")
        let advisor = StubAdvisor(category: "12_Software/Herramientas", confidence: 0.2)
        let refined = await FolderOrderer.planAsync(files: [file], advisor: advisor)
        XCTAssertTrue(refined.first?.isQuarantine ?? false, "confianza < 0,5 vuelve a cuarentena")
    }

    func testPlanAsyncIgnoresUnknownCategoriesFromAI() async throws {
        let file = try makeFile("asdf.qwerty")
        let advisor = StubAdvisor(category: "Categoria Inventada", confidence: 0.99)
        let refined = await FolderOrderer.planAsync(files: [file], advisor: advisor)
        XCTAssertTrue(refined.first?.isQuarantine ?? false, "categoría fuera de la taxonomía → cuarentena")
    }

    func testPlanAsyncWithoutAdvisorMatchesSyncPlan() async throws {
        let file = try makeFile("asdf.qwerty")
        let sync = FolderOrderer.plan(files: [file])
        let async = await FolderOrderer.planAsync(files: [file], advisor: nil)
        XCTAssertEqual(sync, async)
    }

    func testPlanAsyncRespectsMaxCallsAndOnlyConsultsQuarantine() async throws {
        _ = try makeFile("nomina-marzo.pdf")            // las reglas ya lo saben (no gasta IA)
        _ = try makeFile("raro-uno.qwerty")
        _ = try makeFile("raro-dos.qwerty")
        _ = try makeFile("raro-tres.qwerty")

        let files = (try? FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)) ?? []
        let advisor = CountingAdvisor(category: "12_Software/Herramientas", confidence: 0.8)
        let refined = await FolderOrderer.planAsync(
            files: files.sorted { $0.path < $1.path },
            advisor: advisor,
            maxAICalls: 2
        )

        XCTAssertEqual(advisor.calls, 2, "solo 2 llamadas (tope) y ninguna para el fichero de reglas")
        let quarantined = refined.filter { $0.isQuarantine }.count
        XCTAssertEqual(quarantined, 1, "queda 1 dudoso sin consultar")
    }

    func testProposalParsing() throws {
        let content = #"{"category_path": "03_Seguros/Polizas", "confidence": 1.4, "reason": "poliza del coche"}"#
        let proposal = try DeepSeekFilingAdvice.proposal(fromContent: content)
        XCTAssertEqual(proposal.categoryPath, "03_Seguros/Polizas")
        XCTAssertEqual(proposal.confidence, 1.0, "la confianza se recorta a 0…1")
        XCTAssertEqual(proposal.source, .ai)

        XCTAssertThrowsError(try DeepSeekFilingAdvice.proposal(fromContent: "{}"))
        XCTAssertThrowsError(try DeepSeekFilingAdvice.proposal(fromContent: "no-json"))
    }

    func testExtractContentFromEnvelope() throws {
        let envelope = #"{"choices": [{"message": {"content": "{\"category_path\": \"01_Fiscal\"}"}}]}"#
        let content = try DeepSeekFilingAdvice.extractContent(from: Data(envelope.utf8))
        XCTAssertTrue(content.contains("01_Fiscal"))
        XCTAssertThrowsError(try DeepSeekFilingAdvice.extractContent(from: Data("{}".utf8)))
    }
}
