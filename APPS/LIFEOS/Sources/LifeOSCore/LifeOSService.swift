import Foundation
import LifeOSAPI

/// Resultado de capturar: enviada, guardada sin conexión o pendiente de una
/// aclaración.
public enum CaptureOutcome: Sendable {
    case sent(CaptureSummary)
    case queued(OutboxItem)
}

/// El ciclo diario contra la API, con las reglas del producto ya aplicadas.
///
/// Aquí viven las dos cosas que la interfaz no debería tener que recordar:
/// que en producción la clasificación es asíncrona (hay que esperar a que la
/// captura tenga propuesta) y que la propuesta se aplica por operaciones, no
/// entera.
public actor LifeOSService {
    private let client: APIClient
    private let outbox: OutboxStore

    public init(client: APIClient, outbox: OutboxStore = OutboxStore()) {
        self.client = client
        self.outbox = outbox
    }

    // MARK: - Hoy

    public func today() async throws -> (dayClose: DayClose, reminders: UpcomingReminders) {
        async let dayClose = client.dayClose()
        async let reminders = client.upcomingReminders()
        return (try await dayClose, try await reminders)
    }

    public func dayClose() async throws -> DayClose {
        try await client.dayClose()
    }

    public func reminders() async throws -> UpcomingReminders {
        try await client.upcomingReminders()
    }

    // MARK: - Bandeja

    public func inbox(pendingOnly: Bool = true) async throws -> [CaptureDetail] {
        let all = try await client.captures(status: nil)
        guard pendingOnly else { return all }
        return all.filter(\.isPending)
    }

    // MARK: - Capturar

    /// Captura texto.
    ///
    /// Si el servidor no responde, la captura se guarda en la cola local con su
    /// clave de idempotencia y sale sola más tarde: no se pierde una idea por
    /// estar sin cobertura.
    public func capture(_ content: String, sensitivity: String) async throws -> CaptureOutcome {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw APIError.server(status: 422, title: "", detail: "La captura está vacía")
        }
        do {
            let summary = try await client.createCapture(
                content: trimmed,
                sensitivity: sensitivity,
                idempotencyKey: UUID().uuidString
            )
            return .sent(summary)
        } catch let error as APIError {
            guard !error.isNotAuthenticated, case .transport = error else { throw error }
            let item = await outbox.enqueue(content: trimmed, sensitivity: sensitivity)
            return .queued(item)
        }
    }

    /// Espera a que el servidor clasifique la captura y devuelve la propuesta.
    ///
    /// En producción el trabajo lo hace el worker, así que la respuesta inicial
    /// casi nunca trae propuesta: se pregunta hasta que aparezca.
    public func awaitProposal(
        captureId: String,
        attempts: Int = 20,
        interval: Duration = .milliseconds(700)
    ) async throws -> Proposal? {
        for attempt in 0..<max(1, attempts) {
            let status = try await client.captureStatus(id: captureId)
            if let proposalId = status.proposalId {
                return try await client.proposal(id: proposalId)
            }
            if status.status == "needs_clarification" || status.status == "failed" {
                return nil
            }
            if attempt < attempts - 1 {
                try await Task.sleep(for: interval)
            }
        }
        return nil
    }

    public func clarify(captureId: String, answer: String, manualKind: String?) async throws -> CaptureSummary {
        try await client.clarify(
            captureId: captureId,
            answer: answer.trimmingCharacters(in: .whitespacesAndNewlines),
            manualKind: manualKind
        )
    }

    public func proposal(id: String) async throws -> Proposal {
        try await client.proposal(id: id)
    }

    public func apply(proposalId: String, operationIds: [String]) async throws -> Proposal {
        try await client.apply(proposalId: proposalId, operationIds: operationIds)
    }

    public func reject(proposalId: String) async throws -> Proposal {
        try await client.reject(proposalId: proposalId)
    }

    // MARK: - Diario

    public func journal(limit: Int = 60) async throws -> [JournalEntry] {
        try await client.journal(limit: limit)
    }

    public func createJournalEntry(_ payload: JournalEntryRequest) async throws -> JournalEntry {
        try await client.createJournalEntry(payload)
    }

    public func updateJournalEntry(id: String, _ payload: JournalUpdateRequest) async throws -> JournalEntry {
        try await client.updateJournalEntry(id: id, payload)
    }

    public func journalCandidates(query text: String = "", kind: String? = nil, limit: Int = 20) async throws -> [JournalReferenceCandidate] {
        try await client.journalReferenceCandidates(kinds: kind ?? "task,event", query: text, limit: limit)
    }

    /// Borra una entrada (borrado reversible en el servidor).
    public func deleteJournalEntry(id: String) async throws {
        try await client.deleteEntity(id: id)
    }

    // MARK: - Voz

    /// Sube una grabación para que la transcriba el servidor. Con `sensitive` el
    /// audio se guarda y **no** se transcribe (no sale a ningún proveedor).
    @discardableResult
    public func captureAudio(
        data: Data,
        filename: String,
        sensitivity: String,
        language: String = "es"
    ) async throws -> AudioCapture {
        try await client.createAudioCapture(
            data: data,
            filename: filename,
            sensitivity: sensitivity,
            language: language
        )
    }

    // MARK: - Documentos

    /// Sube un documento para que el servidor le saque el texto y lo indexe.
    ///
    /// Quien llama debería haber pasado antes por `EvidenceIntake.plan(for:)`: el
    /// servidor solo admite cuatro extensiones y un tamaño, y un 422 seco no
    /// explica nada. Aquí ya se sube lo que va a subirse.
    @discardableResult
    public func sendDocument(
        data: Data,
        filename: String,
        mimeType: String,
        title: String? = nil,
        sensitivity: String
    ) async throws -> LifeOSDocument {
        try await client.uploadDocument(
            data: data,
            filename: filename,
            mimeType: mimeType,
            title: title,
            sensitivity: sensitivity
        )
    }

    // MARK: - Agenda

    /// Los tres carriles de un día completo (hora local).
    public func agenda(day: Date) async throws -> AgendaDay {
        let bounds = AgendaRange.day(day)
        return try await client.agenda(from: bounds.start, to: bounds.end)
    }

    /// La semana completa que contiene ese día: una sola llamada sirve para la
    /// tira de siete días y para el día elegido.
    public func agenda(weekContaining day: Date) async throws -> AgendaDay {
        let bounds = AgendaRange.week(containing: day)
        return try await client.agenda(from: bounds.start, to: bounds.end)
    }

    @discardableResult
    public func createEvent(_ payload: AgendaEventRequest) async throws -> AgendaEvent {
        try await client.createEvent(payload)
    }

    @discardableResult
    public func updateEvent(id: String, _ payload: AgendaEventUpdate) async throws -> AgendaEvent {
        try await client.updateEvent(id: id, payload)
    }

    @discardableResult
    public func resolveDuplicate(
        taskId: String,
        eventId: String,
        choice: DuplicateChoice
    ) async throws -> DuplicatePair {
        try await client.resolveDuplicate(
            DuplicateResolveRequest(taskId: taskId, eventId: eventId, choice: choice)
        )
    }

    // MARK: - Acciones

    public func tasks() async throws -> [LifeOSTask] {
        try await client.tasks()
    }

    @discardableResult
    public func createTask(_ payload: TaskCreateRequest) async throws -> LifeOSTask {
        try await client.createTask(payload)
    }

    @discardableResult
    public func updateTask(id: String, _ payload: TaskUpdateRequest) async throws -> LifeOSTask {
        try await client.updateTask(id: id, payload)
    }

    /// Marcar como hecha (o reabrir) una acción.
    @discardableResult
    public func setTaskStatus(_ status: String, task: LifeOSTask) async throws -> LifeOSTask {
        try await client.updateTask(
            id: task.id,
            TaskUpdateRequest.status(status, expectedVersion: task.version)
        )
    }

    // MARK: - Buscar y cronología

    public func search(_ query: String) async throws -> SearchResults {
        try await client.search(query)
    }

    public func timeline(days: Int = 7, kinds: [String] = []) async throws -> Timeline {
        try await client.timeline(days: days, kinds: kinds)
    }

    // MARK: - Cola sin conexión

    public func pendingCaptures() async -> [OutboxItem] {
        await outbox.pending()
    }

    public func pendingCount() async -> Int {
        await outbox.count()
    }

    public func forgetQueued(id: String) async {
        await outbox.remove(id: id)
    }

    /// Intenta enviar lo encolado. Devuelve cuántas capturas salieron.
    @discardableResult
    public func flushOutbox() async -> Int {
        var sent = 0
        for item in await outbox.pending() {
            do {
                _ = try await client.createCapture(
                    content: item.content,
                    sensitivity: item.sensitivity,
                    idempotencyKey: item.id
                )
                await outbox.remove(id: item.id)
                sent += 1
            } catch let error as APIError {
                if error.isNotAuthenticated {
                    // Sin sesión no tiene sentido seguir intentándolo.
                    break
                }
                await outbox.markAttempt(id: item.id, error: error.errorDescription)
            } catch {
                await outbox.markAttempt(id: item.id, error: error.localizedDescription)
            }
        }
        return sent
    }
}
