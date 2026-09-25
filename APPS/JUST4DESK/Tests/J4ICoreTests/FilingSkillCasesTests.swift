import XCTest
@testable import J4ICore

/// Regresión de la skill: cada caso curado debe seguir clasificándose como se decidió.
///
/// Régimen de trabajo (decisión del usuario 2026-09-24): cada mala clasificación real acaba aquí
/// como caso nuevo — «un caso nuevo en rojo obliga a arreglar antes de mezclar».
final class FilingSkillCasesTests: XCTestCase {
    func testCuratedFolderCasesMatchLocalRules() {
        for curated in FilingSkill.curatedCases where curated.kind == .folder {
            let proposal = RulesFilingClassifier.classifyFolder(name: curated.name, dominantExtension: curated.hint)
            XCTAssertEqual(
                proposal?.categoryPath,
                curated.expected,
                "Caso curado «\(curated.name)»: \(curated.note)"
            )
        }
    }

    func testCuratedFileCasesMatchLocalRules() {
        for curated in FilingSkill.curatedCases where curated.kind == .file {
            let proposal = RulesFilingClassifier.suggestDestination(fileName: curated.name)
            XCTAssertEqual(
                proposal?.categoryPath,
                curated.expected,
                "Caso curado «\(curated.name)»: \(curated.note)"
            )
        }
    }

    func testSkillIsSubstantialVersionedAndFeedsFewShot() {
        XCTAssertGreaterThanOrEqual(FilingSkill.curatedCases.count, 10)
        XCTAssertGreaterThanOrEqual(FilingSkill.version, 1)
        XCTAssertFalse(FilingSkill.assistantInstructions.isEmpty)
        XCTAssertEqual(FilingSkill.fewShotLines(limit: 3).count, 3)
        // Los few-shot usan el formato esperado y la carpeta «sin clasificar» se representa como 99_SinClasificar.
        let lines = FilingSkill.fewShotLines(limit: FilingSkill.curatedCases.count)
        XCTAssertTrue(lines.contains { $0.contains("→ 99_SinClasificar") })
    }
}
