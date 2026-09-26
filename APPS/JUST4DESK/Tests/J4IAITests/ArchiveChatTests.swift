import XCTest
@testable import J4IAI

/// G7 — prompt y citas del «Chat del archivo».
final class ArchiveChatTests: XCTestCase {
    private func document(_ number: Int, snippetLength: Int) -> ArchiveChatDocument {
        ArchiveChatDocument(
            name: "doc\(number).pdf",
            path: "/tmp/archivo/doc\(number).pdf",
            snippet: String(repeating: "x", count: snippetLength)
        )
    }

    func testPrepareCapsDocuments() {
        let documents = (1...10).map { document($0, snippetLength: 100) }
        let prepared = ArchiveChatPrompt.prepare(documents)
        XCTAssertEqual(prepared.count, ArchiveChatPrompt.maxDocuments)
        XCTAssertEqual(prepared.first?.name, "doc1.pdf")
    }

    func testPrepareTruncatesSnippetsAndRespectsBudget() {
        let documents = (1...6).map { document($0, snippetLength: 2000) }
        let prepared = ArchiveChatPrompt.prepare(documents)
        var total = 0
        for item in prepared {
            XCTAssertLessThanOrEqual(item.snippet.count, ArchiveChatPrompt.maxCharsPerSnippet + 1, "recorte por fragmento (+«…»)")
            XCTAssertFalse(item.snippet.contains("\n"), "los fragmentos van en una línea")
            total += item.snippet.count
        }
        XCTAssertLessThanOrEqual(total, ArchiveChatPrompt.maxTotalSnippetChars + prepared.count, "presupuesto total acotado (margen «…»)")
    }

    func testBuildNumbersDocumentsAndKeepsQuestion() {
        let documents = [document(1, snippetLength: 50), document(2, snippetLength: 50)]
        let (system, user) = ArchiveChatPrompt.build(question: "¿qué facturas hay?", documents: documents)
        XCTAssertTrue(system.contains("español"))
        XCTAssertTrue(system.contains("[1]"))
        XCTAssertTrue(user.contains("¿qué facturas hay?"))
        XCTAssertTrue(user.contains("[1] doc1.pdf"))
        XCTAssertTrue(user.contains("[2] doc2.pdf"))
    }

    func testBuildWithoutDocumentsNotesEmptySearch() {
        let (_, user) = ArchiveChatPrompt.build(question: "¿algo?", documents: [])
        XCTAssertTrue(user.contains("No se han encontrado fragmentos"))
    }

    func testCitedIndicesOrderAndDedupe() {
        let answer = "Según [2] y también [1]. Repito [2]; y fuera de rango [9]."
        XCTAssertEqual(ArchiveChatPrompt.citedIndices(in: answer, documentCount: 3), [2, 1])
    }

    func testCitedIndicesMalformedInputs() {
        XCTAssertEqual(ArchiveChatPrompt.citedIndices(in: "[1]", documentCount: 0), [])
        XCTAssertEqual(ArchiveChatPrompt.citedIndices(in: "[a] [3", documentCount: 3), [])
        XCTAssertEqual(ArchiveChatPrompt.citedIndices(in: "texto sin citas", documentCount: 3), [])
        XCTAssertEqual(ArchiveChatPrompt.citedIndices(in: "[01]", documentCount: 2), [1], "acepta ceros a la izquierda")
    }
}
