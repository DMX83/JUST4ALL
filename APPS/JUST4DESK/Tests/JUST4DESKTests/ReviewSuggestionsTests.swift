import XCTest
@testable import JUST4DESK

/// N2 (ajuste 2026-09-24): la propuesta de la IA se conserva como destino preseleccionado al
/// recargar la cola de revisión — mover un elemento no debe borrar las propuestas del resto
/// («se va la sugerencia de la IA en el menú desplegable»).
final class ReviewSuggestionsTests: XCTestCase {
    func testAIProposalWinsOverRulesSuggestion() {
        XCTAssertEqual(
            ReviewViewModel.effectiveDestination(aiCategory: "12_Software/Redes", aiIsQuarantine: false, rulesSuggestion: nil),
            "12_Software/Redes"
        )
        XCTAssertEqual(
            ReviewViewModel.effectiveDestination(aiCategory: "12_Software/Redes", aiIsQuarantine: false, rulesSuggestion: "14_Comprimidos"),
            "12_Software/Redes"
        )
    }

    func testQuarantineAIProposalFallsBackToRules() {
        XCTAssertEqual(
            ReviewViewModel.effectiveDestination(aiCategory: "99_SinClasificar", aiIsQuarantine: true, rulesSuggestion: "14_Comprimidos"),
            "14_Comprimidos"
        )
    }

    func testWithoutAIProposalRulesSuggestionIsKept() {
        XCTAssertEqual(
            ReviewViewModel.effectiveDestination(aiCategory: nil, aiIsQuarantine: true, rulesSuggestion: "13_Multimedia/Series"),
            "13_Multimedia/Series"
        )
        XCTAssertNil(ReviewViewModel.effectiveDestination(aiCategory: nil, aiIsQuarantine: true, rulesSuggestion: nil))
        XCTAssertNil(ReviewViewModel.effectiveDestination(aiCategory: "", aiIsQuarantine: false, rulesSuggestion: nil))
    }
}
