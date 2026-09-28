import XCTest
@testable import J4IIndex

/// G7 — expansión semántica de consultas (sinónimos locales + expresión FTS estable).
final class QueryExpansionTests: XCTestCase {
    func testTokensNormalization() {
        XCTAssertEqual(QueryExpander.tokens(of: "Sueldo de ENERO!!"), ["sueldo", "de", "enero"])
        XCTAssertEqual(QueryExpander.tokens(of: "   "), [])
        XCTAssertEqual(QueryExpander.tokens(of: "a b c"), [], "los términos de 1 letra se descartan")
        XCTAssertEqual(QueryExpander.tokens(of: "factura-factura"), ["factura"], "sin repetir")
    }

    func testBuildGroupsFormatIsStable() {
        let built = QueryExpander.build(groups: [("sueldo", ["salario", "nomina"]), ("enero", [])])
        XCTAssertEqual(built, "(sueldo* OR salario* OR nomina*) AND enero*")
    }

    func testExpandedQueryUsesSynonymsWhenAvailable() async throws {
        guard let expander = QueryExpander.make() else {
            throw XCTSkip("Sin embeddings de palabras en español en este Mac.")
        }
        let maybeExpanded = await expander.expandedQuery(for: "sueldo")
        let expanded = try XCTUnwrap(maybeExpanded)
        XCTAssertTrue(expanded.contains("sueldo*"))
        XCTAssertTrue(expanded.contains(" OR "), "debería añadir sinónimos: \(expanded)")

        let none = await expander.expandedQuery(for: "zzzzqqxx")
        XCTAssertNil(none, "sin vecinos no hay consulta ampliada")
    }

    func testExpandedQueryKeepsOriginalTokens() async throws {
        guard let expander = QueryExpander.make() else {
            throw XCTSkip("Sin embeddings de palabras en español en este Mac.")
        }
        let maybeExpanded = await expander.expandedQuery(for: "enero factura")
        let expanded = try XCTUnwrap(maybeExpanded)
        XCTAssertTrue(expanded.contains("enero"), expanded)
        XCTAssertTrue(expanded.contains("factura"), expanded)
    }

    func testRetrievalExpressionDropsStopwordsAndExpands() async throws {
        guard let expander = QueryExpander.make() else {
            throw XCTSkip("Sin embeddings de palabras en español en este Mac.")
        }
        let maybe = await expander.retrievalExpression(for: "Que recibos de luz o gas tengo guardados?")
        let expression = try XCTUnwrap(maybe)
        XCTAssertFalse(expression.contains("que*"), "las muletillas se descartan")
        XCTAssertFalse(expression.contains("tengo*"))
        XCTAssertTrue(expression.contains("recibos*"), expression)
        XCTAssertTrue(expression.contains("gas*"), expression)
        XCTAssertTrue(expression.contains(" OR "), "recuperación por OR")
    }

    func testRetrievalExpressionNilWhenOnlyStopwords() async throws {
        guard let expander = QueryExpander.make() else {
            throw XCTSkip("Sin embeddings de palabras en español en este Mac.")
        }
        let none = await expander.retrievalExpression(for: "que de la el los")
        XCTAssertNil(none)
    }
}
