import XCTest

import LifeOSAPI

/// Reglas de presentación y edición de los tokens del diario.
///
/// Estas pruebas son el contrato del espejo en Swift de `web/lib/journal-text.ts`
/// y de los ayudantes del editor de la web: si cambian allí, aquí fallan.
final class JournalTextTests: XCTestCase {
    // MARK: - Tokens

    func testTokenUsesSpanishNames() {
        XCTAssertEqual(JournalText.token(kind: "task", text: "Enviar el informe"), "@tarea:Enviar el informe")
        XCTAssertEqual(JournalText.token(kind: "event", text: "Reunión con Ana"), "@evento:Reunión con Ana")
        XCTAssertEqual(JournalText.token(kind: "decision", text: "Algo"), "@decision:Algo")
    }

    // MARK: - Lectura

    func testSegmentsSplitMentionsOut() {
        let segments = JournalText.segments(in: "Cerré @tarea:Enviar el informe")

        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0], .text("Cerré "))
        XCTAssertEqual(segments[1], .reference(kind: "task", label: "Enviar el informe", trailing: ""))
    }

    /// La sintaxis no tiene cierre: `@tarea:` se come el resto de la línea. Se
    /// replica tal cual la web/server; por eso, al leer, se pasan las referencias
    /// declaradas como frontera (`testDeclaredReferenceBoundsTheChip`).
    func testMentionEatsTheRestOfTheLineLikeTheWeb() {
        let segments = JournalText.segments(in: "Cerré @tarea:Enviar el informe hoy, por fin.")

        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[1], .reference(kind: "task", label: "Enviar el informe hoy, por fin", trailing: "."))
    }

    func testDeclaredReferenceBoundsTheChip() {
        let known = [JournalMention(id: "t1", kind: "task", text: "Enviar el informe")]

        let segments = JournalText.segments(in: "Cerré @tarea:Enviar el informe y me fui a casa.", known: known)

        XCTAssertEqual(segments.count, 3)
        XCTAssertEqual(segments[1], .reference(kind: "task", label: "Enviar el informe", trailing: ""))
        XCTAssertEqual(segments[2], .text(" y me fui a casa."))
    }

    func testTrailingPunctuationStaysInTheSentence() {
        let segments = JournalText.segments(in: "Hablé de @evento:Reunión con Ana.")

        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0], .text("Hablé de "))
        XCTAssertEqual(segments[1], .reference(kind: "event", label: "Reunión con Ana", trailing: "."))
    }

    func testMentionAtTheStartOfTheLine() {
        XCTAssertEqual(
            JournalText.segments(in: "@tarea:Algo importante"),
            [.reference(kind: "task", label: "Algo importante", trailing: "")]
        )
    }

    func testEmailAddressIsNotAMention() {
        // Sin espacio delante no es una referencia: es parte de la palabra.
        XCTAssertEqual(JournalText.segments(in: "escribe a ana@tarea:x"), [.text("escribe a ana@tarea:x")])
    }

    func testEnglishPrefixesAlsoWork() {
        XCTAssertEqual(JournalText.segments(in: "Hecho @task:Algo")[1], .reference(kind: "task", label: "Algo", trailing: ""))
    }

    func testPlainTextReadsMentionsByTheirName() {
        let content = "@hora:22:30\nCerré @tarea:Enviar el informe"

        XCTAssertEqual(JournalText.plainText(content), "Cerré Enviar el informe")
        XCTAssertEqual(JournalText.previewLine(content), "Cerré Enviar el informe")
    }

    func testPlainTextWithDeclaredReferenceKeepsTheProse() {
        let known = [JournalMention(id: "t1", kind: "task", text: "Enviar el informe")]
        let content = "Cerré @tarea:Enviar el informe y me fui a casa."

        XCTAssertEqual(JournalText.plainText(content, known: known), "Cerré Enviar el informe y me fui a casa.")
    }

    // MARK: - Menciones sin vincular

    func testUnlinkedMentionsOnlyReturnsWhatIsNotLinked() {
        let content = "Cerré @tarea:Enviar el informe; me queda @tarea:Llamar al seguro."
        let linked = [JournalMention(id: "t1", kind: "task", text: "Enviar el informe")]

        XCTAssertEqual(
            JournalText.unlinkedMentions(in: content, linked: linked),
            ["Llamar al seguro"]
        )
    }

    func testUnlinkedMentionsDoesNotInventAnything() {
        XCTAssertEqual(JournalText.unlinkedMentions(in: "Hola, sin menciones.", linked: []), [])
        XCTAssertEqual(
            JournalText.unlinkedMentions(in: "Ojo con x@evento:cosa", linked: []),
            [],
            "Sin espacio delante no es una mención"
        )
    }

    func testUnlinkedMentionsAreReadUpToTheNextOne() {
        // Sin cierre, una mención se lee hasta la siguiente arroba o el final de
        // la línea: es la misma regla que la web, no una interpretación libre.
        XCTAssertEqual(
            JournalText.unlinkedMentions(in: "@tarea:Algo y otra vez @tarea:Algo", linked: []),
            ["Algo y otra vez", "Algo"]
        )
    }

    func testUnlinkedMentionsDeduplicatesTheSameLabel() {
        XCTAssertEqual(
            JournalText.unlinkedMentions(in: "@tarea:Algo\n@tarea:Algo", linked: []),
            ["Algo"]
        )
    }

    // MARK: - Guardado

    func testOnlyReferencesStillWrittenAreSent() {
        let mentions = [
            JournalMention(id: "t1", kind: "task", text: "Enviar el informe"),
            JournalMention(id: "t2", kind: "task", text: "Llamar al seguro")
        ]

        // Se borró la segunda mención del texto: ese vínculo deja de existir.
        let content = "Cerré @tarea:Enviar el informe."
        let active = JournalText.activeMentions(mentions, in: content)

        XCTAssertEqual(active.map(\.id), ["t1"])
        XCTAssertEqual(active.map(\.input.targetId), ["t1"])
        XCTAssertEqual(active.first?.input.text, "Enviar el informe")
    }

    // MARK: - Escritura

    func testTypingMentionIsDetected() {
        let query = JournalText.editingMention(in: "Cerré @tar")

        XCTAssertEqual(query?.query, "tar")
        XCTAssertNil(query?.kind)
        XCTAssertEqual(query?.start, 6)
    }

    func testTypingMentionKnowsTheKind() {
        let query = JournalText.editingMention(in: "@tarea:infor")

        XCTAssertEqual(query?.kind, "task")
        XCTAssertEqual(query?.query, "infor")
    }

    func testHeaderTokensDoNotOpenThePicker() {
        XCTAssertNil(JournalText.editingMention(in: "@hora:22:30"), "Es la cabecera, no una referencia")
        XCTAssertNil(JournalText.editingMention(in: "@fecha:20-09-2026"))
        XCTAssertNil(JournalText.editingMention(in: "@ti"), "Todavía se está escribiendo «@time»")
        XCTAssertNil(JournalText.editingMention(in: "Hola, sin arroba"))
        XCTAssertNil(JournalText.editingMention(in: "una direccion de correo "))
    }

    func testInsertionReplacesTheHalfWrittenMention() {
        let text = "Cerré @tar"
        let query = JournalText.editingMention(in: text)

        let result = JournalText.inserting("@tarea:Enviar el informe", into: text, replacing: query)

        XCTAssertEqual(result, "Cerré @tarea:Enviar el informe ")
    }

    func testInsertionAppendsWhenTheButtonIsUsed() {
        XCTAssertEqual(
            JournalText.inserting("@tarea:Algo", into: "Día tranquilo.", replacing: nil),
            "Día tranquilo. @tarea:Algo "
        )
        XCTAssertEqual(
            JournalText.inserting("@evento:Cena", into: "", replacing: nil),
            "@evento:Cena "
        )
        XCTAssertEqual(
            JournalText.inserting("@evento:Cena", into: "Día tranquilo.\n", replacing: nil),
            "Día tranquilo.\n@evento:Cena "
        )
    }
}
