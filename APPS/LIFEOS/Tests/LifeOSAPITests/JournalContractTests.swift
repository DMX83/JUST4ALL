import XCTest

// `@testable` para poder llamar a `JournalLeadHeader.classify`, que es la regla fina del
// servidor (qué valor es hora, cuál fecha y cuál no es nada).
@testable import LifeOSAPI
import TestSupport

/// Contrato del diario: lo que se envía (nombres y campos omitidos) y lo que se
/// lee. Dos cosas del servidor que se comprueban aquí a propósito: el día es un
/// **día** (`"2026-09-30"`, no un instante) y las referencias van aparte del
/// texto, porque no se deducen de él.
final class JournalContractTests: XCTestCase {
    private let base = URL(string: "https://lifeos.example")!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    private func makeClient() -> APIClient {
        APIClient(baseURL: base, token: "t", session: StubURLProtocol.session())
    }

    private func entryJSON(
        id: String = "j1",
        title: String = "",
        content: String = "@hora:22:30\nHoy ha ido bien.",
        mood: Any = 4,
        energy: Any = NSNull(),
        references: [[String: Any]] = [],
        unresolved: [String] = []
    ) -> [String: Any] {
        [
            "id": id,
            "entry_date": "2026-09-30",
            "title": title,
            "content_markdown": content,
            "mood": mood,
            "energy": energy,
            "occurred_at": NSNull(),
            "sensitivity": "sensitive",
            "version": 3,
            "created_at": "2026-09-30T22:31:00+00:00",
            "updated_at": "2026-09-30T22:31:00+00:00",
            "references": references,
            "unresolved_references": unresolved
        ]
    }

    // MARK: - Lectura

    func testDecodesEntryWithDateDayNotInstant() async throws {
        StubURLProtocol.handler = { _ in
            StubURLProtocol.jsonArray([self.entryJSON()])
        }

        let entries = try await makeClient().journal(limit: 30)

        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.entryDate, "2026-09-30")
        XCTAssertEqual(entry.mood, 4)
        XCTAssertNil(entry.energy)
        XCTAssertEqual(entry.version, 3)
        XCTAssertTrue(entry.isPrivate)

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.path, "/api/v1/journal")
        XCTAssertEqual(request.url?.query, "limit=30")
    }

    func testExcerptSkipsTheLeadTokens() async throws {
        StubURLProtocol.handler = { _ in
            StubURLProtocol.jsonArray([
                self.entryJSON(content: "@hora:22:30\n@fecha:29-09-2026\nUna tarde tranquila.")
            ])
        }

        let entries = try await makeClient().journal()
        XCTAssertEqual(entries.first?.excerpt, "Una tarde tranquila.")
    }

    // MARK: - Cabecera del texto (@hora / @fecha)

    func testLeadHeaderIsSplitOff() {
        let parsed = JournalLeadHeader.parse("@hora:22:30\n@fecha:20-09-2026\n\nHola, día raro.")
        XCTAssertEqual(parsed.tokens, ["@hora:22:30", "@fecha:20-09-2026"])
        XCTAssertEqual(parsed.remainder, "Hola, día raro.")
    }

    func testLeadHeaderAcceptsEnglishAliasesAndShortHours() {
        let parsed = JournalLeadHeader.parse("@time:22\n@date:2026-09-30\nCena")
        XCTAssertEqual(parsed.tokens, ["@time:22", "@date:2026-09-30"])
        XCTAssertEqual(parsed.remainder, "Cena")
    }

    func testInvalidTokenIsProseAndIsNotHidden() {
        // El servidor para en el primer token que no entiende: eso es prosa.
        let text = "@hora:xx\nHola"
        let parsed = JournalLeadHeader.parse(text)
        XCTAssertTrue(parsed.tokens.isEmpty)
        XCTAssertEqual(parsed.remainder, text)
    }

    // MARK: - La hora escrita sin «:» (@hora:1100)

    /// `@hora:1100` son las 11:00 y `@hora:830` las 8:30 — como se escribe una hora a mano
    /// (30-sep-2026: el dueño escribió `@Time:1100`, no pasaba nada y parecía roto).
    func testLeadHeaderAcceptsBareHoursWrittenWithoutColon() {
        let parsed = JournalLeadHeader.parse("@Time:1100 Fui a pelarme")
        XCTAssertEqual(parsed.tokens, ["@Time:1100"])
        XCTAssertEqual(parsed.remainder, "Fui a pelarme")
        XCTAssertEqual(parsed.schedule.hour, 11)
        XCTAssertEqual(parsed.schedule.minute, 0)

        XCTAssertEqual(JournalLeadHeader.classify("830", kind: "hora"), .time(hour: 8, minute: 30))
        XCTAssertEqual(JournalLeadHeader.classify("2230", kind: "time"), .time(hour: 22, minute: 30))
        // Y sin distinguir mayúsculas, como el resto de la cabecera.
        XCTAssertEqual(JournalLeadHeader.classify("1100", kind: "HORA"), .time(hour: 11, minute: 0))
        // Una hora de una o dos cifras sigue siendo «en punto».
        XCTAssertEqual(JournalLeadHeader.classify("22", kind: "hora"), .time(hour: 22, minute: 0))
        XCTAssertEqual(JournalLeadHeader.classify("22:30", kind: "hora"), .time(hour: 22, minute: 30))
    }

    /// La regla vale **sólo con prefijo de hora**: un número pelado en `@fecha:` no es una hora.
    func testBareHoursDoNotApplyToDatePrefixes() {
        XCTAssertEqual(JournalLeadHeader.classify("1100", kind: "fecha"), .invalid)
        XCTAssertEqual(JournalLeadHeader.classify("1100", kind: "date"), .invalid)
        let text = "@date:1100 Fui a pelarme"
        let parsed = JournalLeadHeader.parse(text)
        XCTAssertTrue(parsed.tokens.isEmpty, "lo que el servidor no entiende no se oculta")
        XCTAssertEqual(parsed.remainder, text)
        XCTAssertEqual(parsed.schedule.invalid, "1100")
        XCTAssertFalse(parsed.schedule.hasValue)
    }

    /// Y lo que no existe sigue sin ser una hora: 75 minutos o 25 horas no valen.
    func testImpossibleBareHoursAreStillInvalid() {
        XCTAssertEqual(JournalLeadHeader.classify("1175", kind: "hora"), .invalid)
        XCTAssertEqual(JournalLeadHeader.classify("2500", kind: "hora"), .invalid)
        XCTAssertEqual(JournalLeadHeader.classify("99", kind: "hora"), .invalid)
    }

    /// El aviso del compositor necesita saber qué hará la cabecera: día, hora y lo que no se
    /// entendió. Se mira con `schedule(in:)`, que copia la regla del servidor (sigue mirando
    /// tokens aunque uno sea inválido).
    func testScheduleSummarisesDayAndTime() {
        let onlyTime = JournalLeadHeader.schedule(in: "@hora:1100 Fui a pelarme")
        XCTAssertEqual(onlyTime.hour, 11)
        XCTAssertEqual(onlyTime.minute, 0)
        XCTAssertNil(onlyTime.year, "sin @fecha: el día es el de la entrada")
        XCTAssertTrue(onlyTime.hasValue)
        XCTAssertNil(onlyTime.invalid)

        let withDay = JournalLeadHeader.schedule(in: "@hora:1100 @fecha:20-09-2026 Nota")
        XCTAssertEqual(withDay.hour, 11)
        XCTAssertEqual(withDay.year, 2026)
        XCTAssertEqual(withDay.month, 9)
        XCTAssertEqual(withDay.day, 20)

        let empty = JournalLeadHeader.schedule(in: "Un día tranquilo")
        XCTAssertFalse(empty.hasValue)
        XCTAssertNil(empty.invalid)
        XCTAssertNil(empty.hour)
    }

    func testTokenInTheMiddleOfTheTextIsProse() {
        let text = "Hola\n@hora:22:30"
        XCTAssertEqual(JournalLeadHeader.parse(text).remainder, text)
    }

    func testDefaultTitleDoesNotHideTheText() async throws {
        StubURLProtocol.handler = { _ in
            StubURLProtocol.jsonArray([
                self.entryJSON(title: "Entrada del 30 de septiembre", content: "Cerré el informe.")
            ])
        }

        let entries = try await makeClient().journal()
        let entry = try XCTUnwrap(entries.first)

        XCTAssertFalse(entry.hasUserTitle)
        XCTAssertEqual(entry.heading, "Cerré el informe.")
    }

    func testUserTitleWinsInTheList() async throws {
        StubURLProtocol.handler = { _ in
            StubURLProtocol.jsonArray([self.entryJSON(title: "Notas sueltas", content: "Comprar bombillas.")])
        }

        let entries = try await makeClient().journal()
        let entry = try XCTUnwrap(entries.first)

        XCTAssertTrue(entry.hasUserTitle)
        XCTAssertEqual(entry.heading, "Notas sueltas")
    }

    func testDecodesReferencesAndUnresolvedWarnings() async throws {
        StubURLProtocol.handler = { _ in
            StubURLProtocol.jsonArray([
                self.entryJSON(
                    references: [[
                        "id": "t1", "kind": "task", "title": "Enviar el informe",
                        "text": "el informe", "status": "renamed"
                    ]],
                    unresolved: ["@tarea:lo del seguro"]
                )
            ])
        }

        let entries = try await makeClient().journal()
        let entry = try XCTUnwrap(entries.first)

        XCTAssertEqual(entry.references.first?.title, "Enviar el informe")
        XCTAssertTrue(entry.references.first?.wasRenamed == true)
        XCTAssertEqual(entry.unresolvedReferences, ["@tarea:lo del seguro"])
    }

    // MARK: - Escritura

    func testCreateSendsSnakeCaseAndOmitsEmptyOptionals() async throws {
        StubURLProtocol.handler = { _ in
            StubURLProtocol.Stub(status: 201, body: try! JSONSerialization.data(withJSONObject: self.entryJSON()))
        }

        _ = try await makeClient().createJournalEntry(
            JournalEntryRequest(contentMarkdown: "Sólo texto", mood: 5)
        )

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/v1/journal")

        let body = try XCTUnwrap(StubURLProtocol.bodyJSON(of: request))
        XCTAssertEqual(body["content_markdown"] as? String, "Sólo texto")
        XCTAssertEqual(body["mood"] as? Int, 5)
        // El diario es privado por defecto y se dice explícitamente.
        XCTAssertEqual(body["sensitivity"] as? String, "sensitive")
        // Los campos que no se usan no se envían: el servidor pone el día de hoy.
        XCTAssertNil(body["entry_date"])
        XCTAssertNil(body["energy"])
    }

    func testCreateSendsDeclaredReferences() async throws {
        StubURLProtocol.handler = { _ in
            StubURLProtocol.Stub(status: 201, body: try! JSONSerialization.data(withJSONObject: self.entryJSON()))
        }

        _ = try await makeClient().createJournalEntry(
            JournalEntryRequest(
                contentMarkdown: "Cerré @tarea:el informe",
                references: [JournalReferenceInput(targetId: "t1", text: "el informe")]
            )
        )

        let body = try XCTUnwrap(StubURLProtocol.bodyJSON(of: StubURLProtocol.lastRequest!))
        let references = try XCTUnwrap(body["references"] as? [[String: Any]])
        XCTAssertEqual(references.first?["target_id"] as? String, "t1")
        XCTAssertEqual(references.first?["text"] as? String, "el informe")
    }

    /// La zona del dispositivo viaja con la entrada: es lo que hace que `@hora:1100` sean
    /// las 11:00 de **quien escribe**, esté donde esté (1-oct-2026, petición del dueño).
    func testJournalPayloadCarriesTheDeviceTimezone() async throws {
        StubURLProtocol.handler = { _ in
            StubURLProtocol.Stub(status: 201, body: try! JSONSerialization.data(withJSONObject: self.entryJSON()))
        }

        _ = try await makeClient().createJournalEntry(
            JournalEntryRequest(contentMarkdown: "@hora:1100 Fui a pelarme", tz: "Pacific/Auckland")
        )
        var body = try XCTUnwrap(StubURLProtocol.bodyJSON(of: StubURLProtocol.lastRequest!))
        XCTAssertEqual(body["tz"] as? String, "Pacific/Auckland")

        _ = try await makeClient().updateJournalEntry(
            id: "j1",
            JournalUpdateRequest(contentMarkdown: "@hora:1100 Fui a pelarme", tz: "Pacific/Auckland")
        )
        body = try XCTUnwrap(StubURLProtocol.bodyJSON(of: StubURLProtocol.lastRequest!))
        XCTAssertEqual(body["tz"] as? String, "Pacific/Auckland")
    }

    func testUpdateSendsVersionForOptimisticControl() async throws {
        StubURLProtocol.handler = { _ in
            StubURLProtocol.json(self.entryJSON())
        }

        _ = try await makeClient().updateJournalEntry(
            id: "j1",
            JournalUpdateRequest(contentMarkdown: "Corregido", mood: 3, expectedVersion: 3)
        )

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "PATCH")
        XCTAssertEqual(request.url?.path, "/api/v1/journal/j1")
        let body = try XCTUnwrap(StubURLProtocol.bodyJSON(of: request))
        XCTAssertEqual(body["expected_version"] as? Int, 3)
        XCTAssertEqual(body["content_markdown"] as? String, "Corregido")
        XCTAssertNil(body["title"])
    }

    func testUpdateSendsExplicitNullsSoMoodCanBeCleared() async throws {
        StubURLProtocol.handler = { _ in StubURLProtocol.json(self.entryJSON()) }

        // Sin ánimo (nil) y sin nulls explícitos el servidor entendería «no lo
        // toques»; lo que queremos es borrarlo.
        _ = try await makeClient().updateJournalEntry(
            id: "j1",
            JournalUpdateRequest(contentMarkdown: "Hoy no pongo ánimo.", mood: nil, expectedVersion: 1)
        )

        let body = try XCTUnwrap(StubURLProtocol.bodyJSON(of: StubURLProtocol.lastRequest!))
        XCTAssertTrue(body["mood"] is NSNull, "El ánimo tiene que ir como null explícito")
        XCTAssertTrue(body["energy"] is NSNull)
    }

    func testUpdateCanOmitFieldsWhenAsked() async throws {
        StubURLProtocol.handler = { _ in StubURLProtocol.json(self.entryJSON()) }

        _ = try await makeClient().updateJournalEntry(
            id: "j1",
            JournalUpdateRequest(contentMarkdown: "Sólo texto", explicitNulls: false)
        )

        let body = try XCTUnwrap(StubURLProtocol.bodyJSON(of: StubURLProtocol.lastRequest!))
        XCTAssertNil(body["mood"])
        XCTAssertNil(body["energy"])
    }

    func testConflictIsReportedAsSuch() async throws {
        StubURLProtocol.handler = { _ in
            StubURLProtocol.text(#"{"detail":"La entrada cambió desde que la abriste"}"#, status: 409)
        }

        do {
            _ = try await makeClient().updateJournalEntry(
                id: "j1",
                JournalUpdateRequest(contentMarkdown: "Corregido", expectedVersion: 1)
            )
            XCTFail("Debería haber fallado")
        } catch let error as APIError {
            guard case .server(let status, _, let detail) = error else {
                return XCTFail("Error inesperado: \(error)")
            }
            XCTAssertEqual(status, 409)
            XCTAssertTrue(detail.contains("cambió"))
        }
    }

    // MARK: - Candidatos y borrado

    func testReferenceCandidatesQuery() async throws {
        StubURLProtocol.handler = { _ in
            StubURLProtocol.jsonArray([
                ["id": "t1", "kind": "task", "label": "Enviar el informe", "detail": "Trabajo"]
            ])
        }

        let candidates = try await makeClient().journalReferenceCandidates(query: "informe", limit: 5)

        XCTAssertEqual(candidates.first?.label, "Enviar el informe")
        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.path, "/api/v1/journal/reference-candidates")
        XCTAssertEqual(request.url?.query, "kinds=task,event&q=informe&limit=5")
    }

    func testDeleteGoesThroughTheEntityEndpoint() async throws {
        StubURLProtocol.handler = { _ in StubURLProtocol.Stub(status: 200, body: Data(#"{"id":"j1","deleted":true}"#.utf8)) }

        try await makeClient().deleteEntity(id: "j1")

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertEqual(request.url?.path, "/api/v1/entities/j1")
    }
}
