import XCTest
@testable import J4ICore

final class FilingPlannerTests: XCTestCase {
    func testResolveValidProposalBuildsTemplatedName() {
        let proposal = FilingProposal(
            categoryPath: "01_Fiscal/Facturas",
            suggestedTitle: "Factura Luz Marzo",
            confidence: 0.9,
            reason: "test",
            issuer: "Iberdrola",
            documentDate: "2026-03-12",
            source: .ai
        )
        let plan = FilingPlanner.resolve(proposal: proposal, originalFileName: "scan001.pdf")
        XCTAssertEqual(plan.categoryRelativePath, "01_Fiscal/Facturas")
        XCTAssertEqual(plan.fileName, "2026-03-12_Iberdrola_Factura-Luz-Marzo.pdf")
        XCTAssertFalse(plan.isQuarantine)
        XCTAssertEqual(plan.source, .ai)
    }

    func testResolveUnknownCategoryGoesToQuarantine() {
        let proposal = FilingProposal(
            categoryPath: "99_Desconocida",
            suggestedTitle: nil,
            confidence: 0.9,
            reason: "test",
            source: .ai
        )
        let plan = FilingPlanner.resolve(proposal: proposal, originalFileName: "doc.pdf")
        XCTAssertTrue(plan.isQuarantine)
        XCTAssertEqual(plan.categoryRelativePath, "99_SinClasificar")
    }

    func testResolveLowConfidenceGoesToQuarantine() {
        let proposal = FilingProposal(
            categoryPath: "01_Fiscal/Facturas",
            suggestedTitle: nil,
            confidence: 0.3,
            reason: "test",
            source: .ai
        )
        let plan = FilingPlanner.resolve(proposal: proposal, originalFileName: "doc.pdf")
        XCTAssertTrue(plan.isQuarantine)
    }

    func testResolveNilProposalGoesToQuarantineWithOriginalName() {
        let plan = FilingPlanner.resolve(proposal: nil, originalFileName: "carta.pdf")
        XCTAssertTrue(plan.isQuarantine)
        XCTAssertEqual(plan.fileName, "carta.pdf")
        XCTAssertEqual(plan.source, .fallback)
    }

    func testNormalizeCategoryVariants() {
        let allowed = DefaultTaxonomy.allRelativePaths
        XCTAssertEqual(FilingPlanner.normalizeCategory("01_Fiscal/Facturas", allowed: allowed), "01_Fiscal/Facturas")
        XCTAssertEqual(FilingPlanner.normalizeCategory("Fiscal/Facturas", allowed: allowed), "01_Fiscal/Facturas")
        XCTAssertEqual(FilingPlanner.normalizeCategory("facturas", allowed: allowed), "01_Fiscal/Facturas")
        XCTAssertEqual(FilingPlanner.normalizeCategory("NÓMINAS", allowed: allowed), "01_Fiscal/Nominas")
        XCTAssertNil(FilingPlanner.normalizeCategory("Nope/Nope", allowed: allowed))
    }

    func testFileNameFactorySanitizesIllegalCharacters() {
        let name = FileNameFactory.make(
            date: nil,
            issuer: "Banco/Santander: S.A.",
            title: "Extracto *marzo* <2026>",
            originalFileName: "doc.pdf"
        )
        XCTAssertEqual(name, "Banco-Santander-S.A_Extracto-marzo-2026.pdf")
        XCTAssertFalse(name.contains("/"))
        XCTAssertFalse(name.contains(":"))
        XCTAssertFalse(name.contains("*"))
        XCTAssertTrue(name.hasSuffix(".pdf"))
    }

    func testRulesClassifierMatchesNameFirst() {
        let proposal = RulesFilingClassifier.classify(fileName: "Factura-Luz-Marzo.pdf", textSample: "")
        XCTAssertEqual(proposal?.categoryPath, "01_Fiscal/Facturas")
        XCTAssertEqual(proposal?.source, .rules)
        XCTAssertGreaterThan(proposal?.confidence ?? 0, 0.7)
    }

    func testRulesClassifierFallsBackToText() {
        let proposal = RulesFilingClassifier.classify(fileName: "documento.pdf", textSample: "Póliza de seguro del hogar")
        XCTAssertEqual(proposal?.categoryPath, "03_Seguros/Polizas")
    }

    func testRulesClassifierReturnsNilWhenNoMatch() {
        XCTAssertNil(RulesFilingClassifier.classify(fileName: "xyz.pdf", textSample: "nada relevante aquí"))
    }
}
