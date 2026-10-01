import AppKit
import Foundation
import LifeOSAPI
import LifeOSCore

/// Estado de la app y todas las operaciones contra la API.
///
/// Es un único modelo para toda la app a propósito: la ventana principal, el
/// panel de captura rápida y la bandeja muestran lo mismo, así que tener una
/// sola fuente de verdad evita que se contradigan.
@MainActor
public final class LifeOSModel: ObservableObject {
    public enum Phase {
        case restoring
        case signedOut
        case signedIn
    }

    /// En qué punto está la captura en curso.
    public enum DraftState {
        case idle
        case working(String)
        case proposal(Proposal)
        case clarification(captureId: String, question: String)
        case queued(OutboxItem)
    }

    // Sesión y datos
    @Published public private(set) var phase: Phase = .restoring
    @Published public private(set) var user: LifeOSUser?
    @Published public private(set) var dayClose: DayClose?
    @Published public private(set) var reminders: [ReminderItem] = []
    @Published public private(set) var inbox: [CaptureDetail] = []
    @Published public private(set) var queued: [OutboxItem] = []
    @Published public private(set) var journal: [JournalEntry] = []
    @Published public private(set) var busy = false

    // Mensajes
    @Published public var errorMessage: String?
    @Published public var statusMessage: String?

    // Ajustes
    @Published public var serverText: String
    @Published public var sensitiveByDefault: Bool
    @Published public var notifyReminders: Bool
    /// Si está apagado, la app **no** registra ⌥Espacio: el atajo es global y
    /// puede molestar a quien ya usa otro igual (JUST4DESK usa el mismo).
    @Published public var hotKeyEnabled: Bool
    /// Abrir LifeOS al iniciar sesión en el Mac.
    @Published public var launchAtLogin: Bool

    // Captura en curso
    @Published public var draft: String = ""
    @Published public var draftSensitive: Bool
    @Published public var draftState: DraftState = .idle
    @Published public var selectedOperations: Set<String> = []

    // Diario
    /// Texto que se está escribiendo (nueva entrada o edición).
    @Published public var journalText: String = "" {
        didSet {
            // Al insertar una mención o al cargar una entrada el texto cambia
            // por código: eso no es «estar escribiendo @algo».
            guard !journalTextSetting else { return }
            journalTextDidChange()
        }
    }
    @Published public var journalTitle: String = ""
    @Published public var journalMood: Int?
    @Published public var journalEnergy: Int?
    /// Si no es `nil`, se está editando esa entrada en vez de crear una nueva.
    @Published public private(set) var journalEditing: JournalEntry?
    /// Entrada abierta para leer (la lista sólo muestra extractos).
    @Published public var journalOpen: String?
    /// Referencias vinculadas a entidades (`@tarea:`/`@evento:`), por id.
    @Published public private(set) var journalMentions: [JournalMention] = []
    /// Menciones escritas que no están vinculadas: se avisa, no se inventa nada.
    @Published public private(set) var journalUnlinked: [String] = []
    /// Candidatos del selector (búsqueda en curso incluida).
    @Published public private(set) var journalCandidates: [JournalReferenceCandidate] = []
    @Published public private(set) var journalCandidatesLoading = false
    /// Mención a medias que se está escribiendo, si la hay.
    @Published public var journalMentionQuery: JournalText.MentionQuery?
    /// Si el selector está abierto (`nil` = cerrado).
    @Published public var journalPickerQuery: String?
    @Published public var journalPickerKind: String?

    /// De dónde salió el selector: de escribir `@…` o de pulsar el botón.
    public enum JournalPickerSource { case typing, manual }

    private var journalPickerSource: JournalPickerSource?
    private var journalTextSetting = false
    private var journalSearchTask: Task<Void, Never>?
    /// Semana de la agenda que ya está en memoria (para no repetir la llamada).
    private var loadedWeekStart: Date?
    private let calendar = Calendar.current

    /// ¿Está abierto el selector de menciones?
    public var journalPickerOpen: Bool { journalPickerSource != nil }

    // Agenda
    /// La semana cargada (los tres carriles y los pares por resolver).
    @Published public private(set) var agenda: AgendaDay?
    /// El día que se está mirando (por defecto, hoy).
    @Published public var agendaDay: Date = Date()
    @Published public var agendaFilter: AgendaOriginFilter = .all
    /// Formulario de cita abierto (alta o edición).
    @Published public var eventDraft: EventDraft?
    /// Pares acción+evento que la persona decidió no volver a ver.
    @Published public private(set) var resolvedDuplicates: Set<String> = []

    // Acciones
    @Published public private(set) var tasks: [LifeOSTask] = []
    @Published public var taskFilter: TaskFilter = .open
    @Published public var taskDraft: TaskDraft?

    // Buscar y cronología
    @Published public var insightMode: InsightMode = .timeline
    @Published public var searchText: String = ""
    @Published public private(set) var searchResults: SearchResults?
    @Published public private(set) var timeline: Timeline?
    @Published public var timelineDays: Int = 7
    /// Tipos que se quieren ver; vacío quiere decir «todos».
    @Published public var timelineKinds: Set<String> = []

    // Voz
    /// Grabador de voz (micrófono). La vista lo observa directamente.
    public let recorder = VoiceRecorder()
    /// Lo que contestó el servidor a la última nota de voz enviada.
    @Published public private(set) var lastAudio: AudioCapture?
    @Published public private(set) var isSendingAudio = false

    // Enviar a LifeOS (Servicios, arrastrar y soltar, abrir con la app)
    /// El último resultado de «enviar a LifeOS», para enseñarlo donde se pueda ver
    /// aunque la ventana no esté delante (el aviso del sistema lo manda el AppDelegate).
    @Published public private(set) var intakeMessage: String?
    /// Si el mensaje es un problema (rojo) o una buena noticia (verde).
    @Published public private(set) var intakeIsProblem = false
    /// Salida digna cuando lo que llegó no se puede guardar: la ruta como nota.
    /// `label` es lo que se enseña en el botón.
    @Published public private(set) var intakeNoteOffer: (note: String, label: String)?
    @Published public private(set) var intakeBusy = false

    // Diagnóstico
    @Published public private(set) var doctorChecks: [DoctorCheck] = []
    @Published public private(set) var doctorRunning = false
    /// Dónde quedó el informe del último diagnóstico (para poder mirarlo o enviarlo).
    @Published public private(set) var doctorReport: URL?

    private let settings: SettingsStore
    private let client: APIClient
    private let auth: AuthService
    private let service: LifeOSService

    /// La ventana avisa aquí cuando llegan avisos nuevos, para programarlos.
    public var remindersDidUpdate: (([ReminderItem]) -> Void)?

    /// La ventana avisa aquí cuando se cambia la preferencia del atajo global:
    /// hay que registrar o soltar el atajo en caliente, sin reiniciar.
    public var hotKeyPreferenceChanged: ((Bool) -> Void)?

    /// Y aquí cuando se cambia el arranque al iniciar sesión (lo aplica el
    /// AppDelegate, que es quien puede hablar con `SMAppService`).
    public var launchAtLoginChanged: ((Bool) -> Void)?

    public init(settings: SettingsStore = SettingsStore()) {
        self.settings = settings
        self.serverText = settings.baseURLString
        self.sensitiveByDefault = settings.sensitiveByDefault
        self.notifyReminders = settings.notifyReminders
        self.hotKeyEnabled = settings.hotKeyEnabled
        self.launchAtLogin = settings.launchAtLogin
        self.draftSensitive = settings.sensitiveByDefault

        let client = APIClient(baseURL: settings.baseURL)
        self.client = client
        self.auth = AuthService(client: client)
        self.service = LifeOSService(client: client)
    }

    public var isSignedIn: Bool { phase == .signedIn }

    public var serverURL: URL { settings.baseURL }

    /// Última sección abierta (la recuerda `MainView`).
    public var storedPane: String { settings.lastPane ?? "today" }

    public func rememberPane(_ raw: String) {
        settings.lastPane = raw
    }

    /// Sale de «Comprobando la sesión…» sin esperar al llavero o al servidor.
    ///
    /// Necesario porque leer el llavero puede tardar (macOS pide permiso si el
    /// token lo guardó otro binario) y la pantalla de entrada no puede quedarse
    /// en un giro sin salida.
    public func continueWithoutSession() {
        guard phase == .restoring else { return }
        phase = .signedOut
        statusMessage = nil
    }

    // MARK: - Datos de ejemplo (revisión de diseño)

    /// Carga datos de mentira para poder renderizar las pantallas sin servidor.
    ///
    /// No es público a propósito: sólo lo usan las pruebas que generan las
    /// imágenes de revisión visual (`LifeOSUITests`).
    func seedForPreview(
        user: LifeOSUser,
        dayClose: DayClose,
        reminders: [ReminderItem],
        inbox: [CaptureDetail],
        queued: [OutboxItem] = [],
        journal: [JournalEntry] = [],
        journalOpen: String? = nil,
        journalMentions: [JournalMention] = [],
        journalDraft: String = "",
        journalMood: Int? = nil,
        journalEnergy: Int? = nil,
        agenda: AgendaDay? = nil,
        agendaDay: Date? = nil,
        tasks: [LifeOSTask] = [],
        timeline: Timeline? = nil,
        searchResults: SearchResults? = nil,
        insightMode: InsightMode = .timeline,
        eventDraft: EventDraft? = nil,
        taskDraft: TaskDraft? = nil,
        draftState: DraftState = .idle,
        draft: String = ""
    ) {
        self.user = user
        self.dayClose = dayClose
        self.reminders = reminders
        self.inbox = inbox
        self.queued = queued
        self.draftState = draftState
        self.draft = draft
        self.journal = journal
        self.journalOpen = journalOpen
        self.journalMentions = journalMentions
        if !journalDraft.isEmpty {
            setJournalText(journalDraft)
            journalUnlinked = JournalText.unlinkedMentions(in: journalDraft, linked: journalMentions)
        }
        // El ánimo y la energía se siembran aparte: la escala de color (1 → 5) necesita
        // poder revisarse con un valor puesto, no sólo vacía.
        self.journalMood = journalMood
        self.journalEnergy = journalEnergy
        self.agenda = agenda
        if let agendaDay { self.agendaDay = agendaDay }
        self.tasks = tasks
        self.timeline = timeline
        self.searchResults = searchResults
        self.insightMode = insightMode
        self.eventDraft = eventDraft
        self.taskDraft = taskDraft
        // Igual que al capturar de verdad: la propuesta llega con todo elegido
        // y la persona desmarca lo que no quiera.
        if case .proposal(let proposal) = draftState {
            selectedOperations = Set(proposal.operations.map(\.id))
        }
        phase = .signedIn
    }

    // MARK: - Arranque

    public func start() async {
        let restored = await auth.restoreSession()
        if let restored {
            user = restored
            phase = .signedIn
            await refresh()
        } else {
            if let failure = auth.lastRestoreError {
                errorMessage = failure
            }
            phase = .signedOut
        }
        await refreshQueued()
    }

    // MARK: - Sesión

    public func signIn(username: String, password: String, mfaCode: String?) async {
        guard !busy else { return }
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            let user = try await auth.signIn(username: username, password: password, mfaCode: mfaCode)
            self.user = user
            phase = .signedIn
            statusMessage = "Hola, \(user.displayName)."
            await refresh()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func signInWithGoogle(anchor: NSWindow?) async {
        guard !busy else { return }
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            let user = try await auth.signInWithGoogle(anchor: anchor)
            self.user = user
            phase = .signedIn
            statusMessage = "Hola, \(user.displayName)."
            await refresh()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Entra con una sesión que ya existía (la de la web), sin pedir contraseña.
    ///
    /// Es la salida cuando el servidor no tiene el flujo nativo y la cuenta se creó
    /// con Google: la sesión de la web vale igual, porque el servidor acepta el
    /// mismo valor como `Authorization: Bearer`.
    public func adoptSession(token: String) async {
        guard !busy else { return }
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            let user = try await auth.adoptSession(token: token)
            self.user = user
            phase = .signedIn
            statusMessage = "Hola, \(user.displayName)."
            await refresh()
        } catch let error as APIError {
            if case .server(let status, _, _) = error, status == 401 {
                errorMessage = "Esa sesión no vale en este servidor (o ya caducó). Copia de nuevo el valor de `lifeos_session`."
            } else {
                errorMessage = error.errorDescription
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Vincula Google con la cuenta que ya está dentro.
    ///
    /// Es el arreglo de raíz del lío de las dos cuentas: quien entró con Google
    /// sin haber vinculado nada se encontró con una cuenta nueva y vacía, aparte
    /// de la suya de siempre. Con esto, la de siempre pasa a ser la que responde
    /// a ese Google.
    public func linkGoogle() async {
        guard !busy, isSignedIn else { return }
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            let outcome = try await auth.linkGoogle(anchor: NSApp.keyWindow)
            // El `google_linked` de la sesión cambia: se vuelve a leer el perfil.
            if let refreshed = try? await client.me() {
                user = refreshed
            }
            if outcome.didLink {
                statusMessage = outcome.message
            } else {
                errorMessage = outcome.message
            }
        } catch let error as GoogleSignInError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func signOut() async {        await auth.signOut()
        user = nil
        dayClose = nil
        reminders = []
        inbox = []
        draftState = .idle
        phase = .signedOut
        statusMessage = nil
    }

    /// Cierra la sesión sólo porque el servidor la rechazó.
    private func handleExpiredSession() async {
        await auth.signOut()
        user = nil
        phase = .signedOut
        errorMessage = "La sesión ha caducado. Vuelve a iniciar sesión."
    }

    // MARK: - Datos

    public func refresh() async {
        guard phase == .signedIn, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let today = try await service.today()
            dayClose = today.dayClose
            reminders = today.reminders.items
            remindersDidUpdate?(today.reminders.items)
            inbox = try await service.inbox(pendingOnly: settings.inboxFilter == "pending")
            journal = try await service.journal(limit: 60)
            agenda = try await service.agenda(weekContaining: agendaDay)
            loadedWeekStart = AgendaRange.week(containing: agendaDay).start
            tasks = try await service.tasks()
            await flushOutbox()
        } catch let error as APIError {
            if error.isNotAuthenticated {
                await handleExpiredSession()
            } else {
                errorMessage = error.errorDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Capturar

    public func sendDraft() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draftState = .working("Clasificando…")
        errorMessage = nil
        do {
            let outcome = try await service.capture(
                text,
                sensitivity: draftSensitive ? "sensitive" : "standard"
            )
            switch outcome {
            case .queued(let item):
                draft = ""
                draftState = .queued(item)
                await refreshQueued()
            case .sent(let summary):
                draft = ""
                if !summary.clarifyingQuestion.isEmpty {
                    draftState = .clarification(captureId: summary.id, question: summary.clarifyingQuestion)
                    return
                }
                if let proposal = try await service.awaitProposal(captureId: summary.id) {
                    selectedOperations = Set(proposal.operations.map(\.id))
                    draftState = .proposal(proposal)
                } else {
                    draftState = .idle
                    statusMessage = "Guardada. LifeOS la tiene en la bandeja para clasificarla."
                    await refresh()
                }
            }
        } catch {
            draftState = .idle
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Responde a la pregunta aclaratoria: con la respuesta, o eligiendo el tipo
    /// a mano cuando quien captura ya sabe lo que es.
    public func answerClarification(_ answer: String, manualKind: String?) async {
        guard case .clarification(let captureId, _) = draftState else { return }
        draftState = .working("Reclasificando…")
        do {
            let summary = try await service.clarify(captureId: captureId, answer: answer, manualKind: manualKind)
            if let proposal = try await service.awaitProposal(captureId: summary.id, attempts: 12) {
                selectedOperations = Set(proposal.operations.map(\.id))
                draftState = .proposal(proposal)
            } else {
                draftState = .idle
                statusMessage = "Anotado. Puedes revisarlo en la bandeja."
                await refresh()
            }
        } catch {
            draftState = .idle
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func toggleOperation(_ id: String) {
        if selectedOperations.contains(id) {
            selectedOperations.remove(id)
        } else {
            selectedOperations.insert(id)
        }
    }

    public func applySelected() async {
        guard case .proposal(let proposal) = draftState else { return }
        guard !selectedOperations.isEmpty else {
            errorMessage = "Elige al menos una operación para guardar."
            return
        }
        draftState = .working("Guardando…")
        do {
            let updated = try await service.apply(
                proposalId: proposal.id,
                operationIds: Array(selectedOperations)
            )
            statusMessage = updated.status == "partially_applied"
                ? "Guardado en parte: el resto queda en la propuesta."
                : "Guardado en LifeOS."
            selectedOperations = []
            draftState = .idle
            await refresh()
        } catch {
            draftState = .proposal(proposal)
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func rejectDraft() async {
        guard case .proposal(let proposal) = draftState else { return }
        draftState = .working("Descartando…")
        do {
            _ = try await service.reject(proposalId: proposal.id)
            selectedOperations = []
            draftState = .idle
            statusMessage = "Descartada sin guardar nada."
            await refresh()
        } catch {
            draftState = .proposal(proposal)
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func resetDraft() {
        draftState = .idle
        selectedOperations = []
        draft = ""
    }

    public func dismissQueuedNotice() {
        if case .queued = draftState {
            draftState = .idle
        }
    }

    // MARK: - Diario

    /// Entradas agrupadas por día, del más reciente al más antiguo.
    public var journalByDay: [(day: String, entries: [JournalEntry])] {
        var order: [String] = []
        var groups: [String: [JournalEntry]] = [:]
        for entry in journal {
            if groups[entry.entryDate] == nil {
                order.append(entry.entryDate)
                groups[entry.entryDate] = []
            }
            groups[entry.entryDate]?.append(entry)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }

    /// Entradas de **hoy**, para la tarjeta de «Hoy»: se compara con el día de
    /// hoy, no con el día de la última entrada escrita (que puede ser de ayer).
    public var journalTodayCount: Int {
        let today = TimeFormatting.dayString()
        return journal.filter { $0.entryDate == today }.count
    }

    public func startJournalEntry() {
        journalEditing = nil
        setJournalText("")
        journalTitle = ""
        journalMood = nil
        journalEnergy = nil
        journalMentions = []
        journalUnlinked = []
        closeJournalPicker()
    }

    public func editJournalEntry(_ entry: JournalEntry) {
        journalEditing = entry
        // El título por defecto lo pone el servidor: no se le enseña al usuario
        // como si lo hubiera escrito él.
        journalTitle = entry.hasUserTitle ? entry.title : ""
        setJournalText(entry.contentMarkdown)
        journalMood = entry.mood
        journalEnergy = entry.energy
        journalOpen = entry.id
        // Las referencias ya vinculadas vuelven al selector: editar el texto sin
        // perder los vínculos que ya existían.
        journalMentions = entry.mentions
        journalUnlinked = entry.unresolvedReferences
        closeJournalPicker()
    }

    public func cancelJournalEdit() {
        startJournalEntry()
    }

    /// Cambiar el texto por código (editar una entrada, insertar una mención) no
    /// es escribir una mención a medias: por eso no se abre el selector solo.
    private func setJournalText(_ text: String) {
        journalTextSetting = true
        journalText = text
        journalTextSetting = false
    }

    private func journalTextDidChange() {
        let query = JournalText.editingMention(in: journalText)
        journalMentionQuery = query
        if let query {
            journalPickerSource = .typing
            journalPickerQuery = query.query
            journalPickerKind = query.kind
            scheduleCandidateSearch()
        } else if journalPickerSource == .typing {
            closeJournalPicker()
        }
        refreshUnlinkedMentions()
    }

    private func refreshUnlinkedMentions() {
        journalUnlinked = JournalText.unlinkedMentions(in: journalText, linked: journalMentions)
    }

    // MARK: - Selector de menciones

    /// Abre el selector a mano (botón), sin depender de lo que se esté escribiendo.
    public func openJournalPicker() {
        journalPickerSource = .manual
        journalPickerQuery = ""
        journalPickerKind = nil
        scheduleCandidateSearch()
    }

    public func closeJournalPicker() {
        journalSearchTask?.cancel()
        journalSearchTask = nil
        journalMentionQuery = nil
        journalPickerSource = nil
        journalPickerQuery = nil
        journalPickerKind = nil
        journalCandidates = []
    }

    /// La búsqueda se espera un momento a que se deje de teclear (como la web).
    private func scheduleCandidateSearch() {
        journalSearchTask?.cancel()
        let text = journalPickerQuery ?? ""
        let kind = journalPickerKind
        journalSearchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }
            await self?.loadJournalCandidates(query: text, kind: kind)
        }
    }

    public func loadJournalCandidates(query text: String, kind: String?) async {
        guard phase == .signedIn else { return }
        journalCandidatesLoading = true
        defer { journalCandidatesLoading = false }
        do {
            journalCandidates = try await service.journalCandidates(query: text, kind: kind)
        } catch {
            journalCandidates = []
        }
    }

    /// Mete la referencia en el texto y la deja vinculada.
    public func applyJournalCandidate(_ candidate: JournalReferenceCandidate) {
        let token = JournalText.token(for: candidate)
        guard !journalMentions.contains(where: { $0.id == candidate.id && $0.token == token }) else {
            closeJournalPicker()
            return
        }
        let replacing = journalPickerSource == .typing ? journalMentionQuery : nil
        setJournalText(JournalText.inserting(token, into: journalText, replacing: replacing))
        journalMentions.append(JournalMention(id: candidate.id, kind: candidate.kind, text: candidate.label))
        closeJournalPicker()
        refreshUnlinkedMentions()
    }

    /// Quita una referencia ya vinculada (el texto escrito se respeta).
    public func removeJournalMention(_ mention: JournalMention) {
        journalMentions.removeAll { $0.id == mention.id }
        refreshUnlinkedMentions()
    }

    public var canSaveJournalEntry: Bool {
        !journalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !busy
    }

    public func saveJournalEntry() async {
        let text = journalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let title = journalTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        // Sólo se declaran las referencias cuyo token sigue escrito: si se borró
        // la mención, el vínculo deja de existir (igual que en la web).
        let references = JournalText.activeMentions(journalMentions, in: text).map(\.input)
        let unlinked = JournalText.unlinkedMentions(in: text, linked: journalMentions)
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            if let editing = journalEditing {
                let payload = JournalUpdateRequest(
                    title: title,
                    contentMarkdown: text,
                    mood: journalMood,
                    energy: journalEnergy,
                    references: references,
                    expectedVersion: editing.version
                )
                _ = try await service.updateJournalEntry(id: editing.id, payload)
                statusMessage = journalStatus(prefix: "Entrada actualizada", references: references, unlinked: unlinked)
                journalOpen = editing.id
            } else {
                let payload = JournalEntryRequest(
                    title: title,
                    contentMarkdown: text,
                    mood: journalMood,
                    energy: journalEnergy,
                    references: references
                )
                let created = try await service.createJournalEntry(payload)
                statusMessage = journalStatus(prefix: "Anotado en el diario", references: references, unlinked: unlinked)
                journalOpen = created.id
            }
            startJournalEntry()
            journal = try await service.journal(limit: 60)
            dayClose = try? await service.dayClose()
        } catch let error as APIError {
            if error.isNotAuthenticated {
                await handleExpiredSession()
            } else if case .server(let status, _, _) = error, status == 409 {
                errorMessage = "Esa entrada cambió en otro sitio desde que la abriste. Vuelve a cargarla y repite el cambio."
            } else {
                errorMessage = error.errorDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func journalStatus(prefix: String, references: [JournalReferenceInput], unlinked: [String]) -> String {
        var parts = [prefix]
        if !references.isEmpty {
            parts.append(references.count == 1 ? "con 1 referencia" : "con \(references.count) referencias")
        }
        var message = parts.joined(separator: " ") + "."
        if !unlinked.isEmpty {
            message += " Sin vincular: \(unlinked.joined(separator: ", "))."
        }
        return message
    }

    /// Borrado reversible (el servidor conserva 30 días).
    public func deleteJournalEntry(_ entry: JournalEntry) async {
        busy = true
        defer { busy = false }
        do {
            try await service.deleteJournalEntry(id: entry.id)
            statusMessage = "Entrada a la papelera. Se puede recuperar desde la web."
            if journalOpen == entry.id { journalOpen = nil }
            if journalEditing?.id == entry.id { startJournalEntry() }
            journal = try await service.journal(limit: 60)
            dayClose = try? await service.dayClose()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func toggleJournalEntry(_ entry: JournalEntry) {
        journalOpen = journalOpen == entry.id ? nil : entry.id
    }

    // MARK: - Agenda

    /// Días de la semana que se está mirando.
    public var agendaWeek: [Date] {
        AgendaRange.days(ofWeekContaining: agendaDay)
    }

    /// Citas del día elegido (sin contar bloques de foco, que van en su carril).
    public var agendaAppointments: [AgendaEvent] {
        events(of: agendaDay).filter { !$0.isFocusBlock }
    }

    /// Bloques de foco del día (eventos con destino y acciones con hora).
    public var agendaFocusBlocks: [AgendaEvent] {
        events(of: agendaDay).filter(\.isFocusBlock)
    }

    /// Acciones con hora reservada ese día (el segundo carril).
    public var agendaScheduledTasks: [LifeOSTask] {
        tasks(of: agendaDay).filter(\.isScheduled)
    }

    /// Vencimientos: acciones con fecha pero sin hora.
    public var agendaDueTasks: [LifeOSTask] {
        tasks(of: agendaDay).filter { !$0.isScheduled }
    }

    /// Los pares que de verdad hay que preguntar (los que ya se decidieron, no).
    public var agendaDuplicates: [DuplicatePair] {
        (agenda?.duplicates ?? []).filter { $0.isPending && !resolvedDuplicates.contains($0.id) }
    }

    /// Cuántas cosas tiene un día, para la tira de la semana.
    public func agendaLoad(of day: Date) -> Int {
        events(of: day).count + tasks(of: day).count
    }

    private func events(of day: Date) -> [AgendaEvent] {
        let bounds = AgendaRange.day(day)
        let calendar = Calendar.current
        return (agenda?.events ?? [])
            .filter { !$0.isCancelled }
            .filter { calendar.isDate($0.startsAt, inSameDayAs: bounds.start) }
            .filter(matchesAgendaFilter)
    }

    private func tasks(of day: Date) -> [LifeOSTask] {
        let calendar = Calendar.current
        let all = (agenda?.tasks ?? []) + (agenda?.dueTasks ?? [])
        return all.filter(matchesAgendaFilter).filter { task in
            guard let reference = task.scheduledStart ?? task.dueDate else { return false }
            return calendar.isDate(reference, inSameDayAs: day)
        }
    }

    private func matchesAgendaFilter(_ event: AgendaEvent) -> Bool {
        switch agendaFilter {
        case .all: return true
        case .lifeos: return !event.isFromGoogle
        case .google: return event.isFromGoogle
        }
    }

    private func matchesAgendaFilter(_ task: LifeOSTask) -> Bool {
        switch agendaFilter {
        case .all: return true
        case .lifeos: return !task.isFromGoogle
        case .google: return task.isFromGoogle
        }
    }

    /// Carga la semana del día elegido (una sola llamada sirve para los siete días).
    public func loadAgenda() async {
        guard phase == .signedIn else { return }
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            agenda = try await service.agenda(weekContaining: agendaDay)
            loadedWeekStart = AgendaRange.week(containing: agendaDay).start
            resolvedDuplicates = []
        } catch let error as APIError {
            if error.isNotAuthenticated {
                await handleExpiredSession()
            } else {
                errorMessage = error.errorDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Cambia el día que se mira. Si cae en la semana ya cargada, no va al servidor.
    public func selectAgendaDay(_ day: Date) async {
        agendaDay = day
        let week = AgendaRange.week(containing: day).start
        if let loaded = loadedWeekStart, calendar.isDate(loaded, inSameDayAs: week) { return }
        await loadAgenda()
    }

    public func stepAgendaDay(_ days: Int) async {
        await selectAgendaDay(AgendaRange.day(agendaDay, offset: days))
    }

    // MARK: - Citas y bloques

    public func startEvent(on day: Date, hour: Int = 9) {
        let calendar = Calendar.current
        let start = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
        let end = calendar.date(byAdding: .hour, value: 1, to: start) ?? start.addingTimeInterval(3600)
        eventDraft = EventDraft(title: "", startsAt: start, endsAt: end)
    }

    public func editEvent(_ event: AgendaEvent) {
        eventDraft = EventDraft(
            id: event.id,
            title: event.title,
            startsAt: event.startsAt,
            endsAt: event.endsAt,
            allDay: event.allDay,
            location: event.location,
            notes: event.notes,
            version: event.version
        )
    }

    public func cancelEventDraft() {
        eventDraft = nil
    }

    public var canSaveEvent: Bool {
        guard let draft = eventDraft else { return false }
        return !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && draft.endsAt > draft.startsAt
            && !busy
    }

    public func saveEvent() async {
        guard let draft = eventDraft, canSaveEvent else { return }
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            if let id = draft.id {
                try await service.updateEvent(
                    id: id,
                    AgendaEventUpdate(
                        title: title,
                        startsAt: draft.startsAt,
                        endsAt: draft.endsAt,
                        allDay: draft.allDay,
                        location: draft.location,
                        notes: draft.notes,
                        status: "scheduled",
                        expectedVersion: draft.version
                    )
                )
                statusMessage = "Cita actualizada."
            } else {
                try await service.createEvent(
                    AgendaEventRequest(
                        title: title,
                        startsAt: draft.startsAt,
                        endsAt: draft.endsAt,
                        allDay: draft.allDay,
                        location: draft.location,
                        notes: draft.notes
                    )
                )
                statusMessage = "Cita creada."
            }
            eventDraft = nil
            agenda = try await service.agenda(weekContaining: agendaDay)
            dayClose = try? await service.dayClose()
        } catch let error as APIError {
            if error.isNotAuthenticated {
                await handleExpiredSession()
            } else if case .server(let status, _, _) = error, status == 409 {
                errorMessage = "Esa cita cambió en otro sitio desde que la abriste. Vuelve a cargarla y repite el cambio."
            } else {
                errorMessage = error.errorDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Marca una cita como hecha (la decisión del par acción+evento se guarda aparte).
    public func completeEvent(_ event: AgendaEvent) async {
        await patchEventStatus(event, status: "completed")
    }

    private func patchEventStatus(_ event: AgendaEvent, status: String) async {
        busy = true
        defer { busy = false }
        do {
            try await service.updateEvent(
                id: event.id,
                AgendaEventUpdate(
                    title: event.title,
                    startsAt: event.startsAt,
                    endsAt: event.endsAt,
                    allDay: event.allDay,
                    location: event.location,
                    notes: event.notes,
                    status: status,
                    expectedVersion: event.version
                )
            )
            agenda = try await service.agenda(weekContaining: agendaDay)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func resolveDuplicate(_ pair: DuplicatePair, choice: DuplicateChoice) async {
        busy = true
        defer { busy = false }
        do {
            try await service.resolveDuplicate(taskId: pair.taskId, eventId: pair.eventId, choice: choice)
            resolvedDuplicates.insert(pair.id)
            statusMessage = choice == .different
                ? "Anotado: son cosas distintas."
                : "Anotado: son la misma cosa."
            agenda = try await service.agenda(weekContaining: agendaDay)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Acciones

    /// Las acciones que se están viendo, según el filtro.
    public var visibleTasks: [LifeOSTask] {
        switch taskFilter {
        case .open: return tasks.filter(\.isOpen)
        case .today:
            let calendar = Calendar.current
            return tasks.filter { task in
                guard task.isOpen, let due = task.dueDate else { return false }
                return calendar.isDateInToday(due) || due < Date()
            }
        case .all: return tasks
        case .done: return tasks.filter { !$0.isOpen }
        }
    }

    public var visibleTasksByStatus: [(status: String, items: [LifeOSTask])] {
        let order = ["doing", "todo", "inbox", "done", "cancelled"]
        let grouped = Dictionary(grouping: visibleTasks, by: \.status)
        return order.compactMap { status in
            guard let items = grouped[status], !items.isEmpty else { return nil }
            return (status, items)
        }
    }

    public func loadTasks() async {
        guard phase == .signedIn else { return }
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            tasks = try await service.tasks()
        } catch let error as APIError {
            if error.isNotAuthenticated {
                await handleExpiredSession()
            } else {
                errorMessage = error.errorDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func startTask() {
        taskDraft = TaskDraft(title: "")
    }

    public func cancelTaskDraft() {
        taskDraft = nil
    }

    public var canSaveTask: Bool {
        guard let draft = taskDraft else { return false }
        return !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !busy
    }

    public func saveTask() async {
        guard let draft = taskDraft, canSaveTask else { return }
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            try await service.createTask(
                TaskCreateRequest(
                    title: title,
                    priority: draft.priority,
                    dueDate: draft.dueDate,
                    context: draft.context.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            )
            taskDraft = nil
            statusMessage = "Acción creada."
            tasks = try await service.tasks()
            dayClose = try? await service.dayClose()
        } catch let error as APIError {
            if error.isNotAuthenticated {
                await handleExpiredSession()
            } else {
                errorMessage = error.errorDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func setTaskStatus(_ task: LifeOSTask, _ status: String) async {
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            let updated = try await service.setTaskStatus(status, task: task)
            if let index = tasks.firstIndex(where: { $0.id == updated.id }) {
                tasks[index] = updated
            }
            // La agenda de la semana también cambia: una acción hecha deja de
            // contar como vencimiento.
            agenda = try? await service.agenda(weekContaining: agendaDay)
            dayClose = try? await service.dayClose()
        } catch let error as APIError {
            if error.isNotAuthenticated {
                await handleExpiredSession()
            } else if case .server(let status, _, _) = error, status == 409 {
                errorMessage = "Esa acción cambió en otro sitio. Actualiza y repite."
            } else {
                errorMessage = error.errorDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func toggleTask(_ task: LifeOSTask) async {
        await setTaskStatus(task, task.isDone ? "todo" : "done")
    }

    // MARK: - Buscar y cronología

    public func runSearch() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = nil
            return
        }
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            searchResults = try await service.search(query)
        } catch let error as APIError {
            if error.isNotAuthenticated {
                await handleExpiredSession()
            } else {
                errorMessage = error.errorDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func loadTimeline() async {
        guard phase == .signedIn else { return }
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            timeline = try await service.timeline(
                days: timelineDays,
                kinds: timelineKinds.sorted()
            )
        } catch let error as APIError {
            if error.isNotAuthenticated {
                await handleExpiredSession()
            } else {
                errorMessage = error.errorDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func clearSearch() {
        searchText = ""
        searchResults = nil
    }

    // MARK: - Voz

    public func startRecording() async {
        errorMessage = nil
        lastAudio = nil
        await recorder.start()
    }

    public func cancelRecording() {
        recorder.cancel()
    }

    /// Termina la grabación y la envía. Si la nota es sensible, el servidor
    /// guarda el audio y **no** lo transcribe; la app lo dice tal cual.
    public func sendRecording() async {
        guard let recording = recorder.stop() else { return }
        isSendingAudio = true
        errorMessage = nil
        defer { isSendingAudio = false }
        do {
            let capture = try await service.captureAudio(
                data: recording.data,
                filename: recording.filename,
                sensitivity: draftSensitive ? "sensitive" : "standard"
            )
            lastAudio = capture
            if capture.isStoredOnly {
                statusMessage = "Nota guardada sin transcribir (es privada). El audio está en LifeOS."
            } else if capture.didFailTranscription {
                errorMessage = "El audio se ha guardado, pero el servidor no pudo transcribirlo."
            } else {
                statusMessage = "Nota transcrita y en la bandeja, por clasificar."
            }
            inbox = (try? await service.inbox(pendingOnly: false)) ?? inbox
            dayClose = try? await service.dayClose()
        } catch let error as APIError {
            if error.isNotAuthenticated {
                await handleExpiredSession()
            } else {
                errorMessage = error.errorDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Diagnóstico del servidor

    /// Comprueba el servidor al que apunta la app: salud, qué endpoints tiene,
    /// si la sesión vale y **si cada pantalla se entiende** (el JSON encaja con
    /// los modelos). Deja un informe en disco para poder enseñarlo tal cual.
    public func runDoctor() async {
        guard !doctorRunning else { return }
        doctorRunning = true
        defer { doctorRunning = false }
        let server = settings.baseURL
        let token = await client.currentToken()
        let checks = await ServerDoctor.run(baseURL: server, token: token)
        doctorChecks = checks
        doctorReport = writeDoctorReport(checks, server: server)
        let failures = checks.filter { $0.level == .failure }.count
        if failures > 0 {
            errorMessage = nil
            statusMessage = nil
            errorMessage = "El diagnóstico encontró \(failures) problema(s). Está el detalle en Ajustes."
        } else {
            statusMessage = "Diagnóstico del servidor: \(ServerDoctor.summary(checks))."
        }
    }

    /// El informe va sin la sesión dentro: se puede enseñar o pegar sin cuidado.
    private func writeDoctorReport(_ checks: [DoctorCheck], server: URL) -> URL? {
        let stamp = ISO8601DateFormatter().string(from: Date())
        var lines = [
            "Diagnóstico de LifeOS",
            "Servidor: \(server.absoluteString)",
            "Cuándo: \(stamp)",
            "Resumen: \(ServerDoctor.summary(checks))",
            String(repeating: "-", count: 64)
        ]
        for check in checks {
            lines.append("\(check.level.symbol) \(check.title)")
            lines.append("   \(check.detail)")
        }
        let text = lines.joined(separator: "\n") + "\n"

        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let directory = support.appendingPathComponent("LIFEOS", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("diagnostico-servidor.txt")
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    // MARK: - Cola sin conexión

    public func refreshQueued() async {
        queued = await service.pendingCaptures()
    }

    @discardableResult
    public func flushOutbox() async -> Int {
        let sent = await service.flushOutbox()
        await refreshQueued()
        if sent > 0 {
            statusMessage = sent == 1
                ? "Se envió la captura que estaba sin conexión."
                : "Se enviaron \(sent) capturas que estaban sin conexión."
        }
        return sent
    }

    public func forgetQueued(id: String) async {
        await service.forgetQueued(id: id)
        await refreshQueued()
    }

    // MARK: - Enviar a LifeOS

    /// Recibe algo de **fuera** de la app: una selección del menú Servicios, un
    /// fichero abierto con LifeOS o algo arrastrado a la ventana.
    ///
    /// Devuelve `true` cuando el texto ha ido al flujo de captura y hay que
    /// enseñar la propuesta (el AppDelegate abre el panel si la app no está
    /// delante). Un fichero no necesita revisión: se sube y se cuenta.
    @discardableResult
    public func receive(_ incoming: Incoming) async -> Bool {
        intakeNoteOffer = nil
        switch EvidenceIntake.plan(for: incoming) {
        case .capture(let text):
            draft = text
            await sendDraft()
            return true
        case .upload(let file, let filename, let mimeType):
            await uploadDocument(file: file, filename: filename, mimeType: mimeType)
            return false
        case .refuse(let reason, let note):
            intakeIsProblem = true
            intakeMessage = reason
            intakeNoteOffer = note.map { (note: $0, label: "Anotar la ruta como nota") }
            return false
        }
    }

    /// Varios ficheros de golpe (arrastrar una selección). Se mandan uno a uno
    /// para que un fichero malo no tumbe a los demás, y se resume al final.
    public func receive(files: [URL]) async {
        guard !files.isEmpty else { return }
        var saved = 0
        var problems: [String] = []
        for url in files {
            let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
            switch EvidenceIntake.plan(for: .file(url, size: size)) {
            case .upload(let file, let filename, let mimeType):
                if await uploadDocument(file: file, filename: filename, mimeType: mimeType) {
                    saved += 1
                } else if let message = intakeMessage {
                    problems.append(message)
                }
            case .refuse(let reason, let note):
                problems.append(reason)
                if let note {
                    // La última salida ofrecida gana: solo hay sitio para una.
                    intakeNoteOffer = (note: note, label: "Anotar la ruta como nota")
                }
            case .capture:
                // Un fichero nunca acaba aquí; si el plan cambiara, se dice en vez
                // de tragárselo en silencio.
                problems.append("«\(url.lastPathComponent)» no se pudo enviar como documento.")
            }
        }
        if problems.isEmpty {
            intakeIsProblem = false
            intakeMessage = saved == 1
                ? "Un documento enviado a LifeOS."
                : "\(saved) documentos enviados a LifeOS."
        } else {
            intakeIsProblem = true
            intakeMessage = problems.joined(separator: " ")
        }
    }

    /// Sube un documento. Devuelve `true` si se guardó.
    @discardableResult
    private func uploadDocument(file: URL, filename: String, mimeType: String) async -> Bool {
        intakeBusy = true
        defer { intakeBusy = false }
        do {
            // Leer el fichero fuera del hilo principal: uno de 20 MB no debería
            // congelar la ventana.
            let data = try await Task.detached(priority: .userInitiated) {
                try Data(contentsOf: file, options: .mappedIfSafe)
            }.value
            let document = try await service.sendDocument(
                data: data,
                filename: filename,
                mimeType: mimeType,
                title: EvidenceIntake.title(for: file),
                sensitivity: sensitiveByDefault ? "sensitive" : "standard"
            )
            intakeIsProblem = false
            intakeMessage = document.confirmation
            await refresh()
            return true
        } catch let error as APIError where error.isDuplicateDocument {
            // No es un fallo: ese documento ya estaba.
            intakeIsProblem = false
            intakeMessage = "«\(filename)» ya estaba en LifeOS: no se ha duplicado."
            return false
        } catch {
            intakeIsProblem = true
            intakeMessage = "No se pudo enviar «\(filename)»: "
                + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            return false
        }
    }

    /// Acepta la salida que se ofreció cuando un fichero no se podía guardar:
    /// apuntar la ruta como nota, para no perder de dónde venía.
    public func acceptIntakeNote() async {
        guard let offer = intakeNoteOffer else { return }
        intakeNoteOffer = nil
        draft = offer.note
        await sendDraft()
    }

    public func dismissIntakeMessage() {
        intakeMessage = nil
        intakeNoteOffer = nil
    }

    // MARK: - Ajustes

    public func savePreferences() {
        settings.sensitiveByDefault = sensitiveByDefault
        settings.notifyReminders = notifyReminders
        settings.hotKeyEnabled = hotKeyEnabled
        settings.launchAtLogin = launchAtLogin
        hotKeyPreferenceChanged?(hotKeyEnabled)
        launchAtLoginChanged?(launchAtLogin)
        statusMessage = "Preferencias guardadas."
    }

    public func applyServerChange() async {
        guard let url = SettingsStore.normalize(serverText) else {
            errorMessage = "Esa dirección no parece válida. Ejemplo: https://lifeos.perlatec.net"
            return
        }
        settings.baseURLString = url.absoluteString
        serverText = url.absoluteString
        await auth.changeServer(to: url)
        user = nil
        dayClose = nil
        reminders = []
        inbox = []
        phase = .signedOut
        statusMessage = "Servidor actualizado. Inicia sesión otra vez."
    }

    /// Comprueba que el servidor responde antes de pedir credenciales.
    public func probeServer() async -> Bool {
        do {
            try await client.probeServer()
            return true
        } catch {
            errorMessage = "El servidor no respondió: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
            return false
        }
    }

    // MARK: - Web

    /// La consola completa sigue en la web: la app abre la sección que no cubre.
    public func openWeb(path: String = "/") {
        guard let url = LifeOSEndpoint.url(base: settings.baseURL, path: path) else { return }
        NSWorkspace.shared.open(url)
    }
}
