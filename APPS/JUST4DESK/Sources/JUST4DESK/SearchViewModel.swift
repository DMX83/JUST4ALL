import Foundation
import AppKit
import J4IAI
import J4ICore
import J4IDocs
import J4IFiling
import J4IIndex

/// Estado y lógica de la UI de búsqueda (F2).
///
/// Contratos:
/// - Todas las queries van contra `SearchIndex` (nunca se recorre el árbol).
/// - Debounce de 120 ms y cancelación de queries obsoletas (task token).
/// - El estado de las raíces se refresca por polling (1 s) para mostrar progreso de indexado.
@MainActor
final class SearchViewModel: ObservableObject {
    /// Clave de preferencia (UserDefaults): buscar también dentro del contenido.
    private static let contentSearchDefaultsKey = "just4desk.search.inContent"

    // MARK: - Tipos

    enum ResultKindFilter: String, CaseIterable, Identifiable {
        case all
        case documents
        case images
        case audio
        case video
        case archives

        var id: String { rawValue }

        var label: String {
            switch self {
            case .all: return "Todo"
            case .documents: return "Documentos"
            case .images: return "Imágenes"
            case .audio: return "Audio"
            case .video: return "Vídeo"
            case .archives: return "Comprimidos"
            }
        }

        var symbolName: String {
            switch self {
            case .all: return "square.grid.2x2"
            case .documents: return "doc.text"
            case .images: return "photo"
            case .audio: return "music.note"
            case .video: return "film"
            case .archives: return "archivebox"
            }
        }

        var extensions: Set<String>? {
            switch self {
            case .all:
                return nil
            case .documents:
                return ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "md", "rtf", "csv"]
            case .images:
                return ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "tiff", "bmp", "svg"]
            case .audio:
                return ["mp3", "m4a", "aac", "wav", "aiff", "flac", "alac", "ogg"]
            case .video:
                return ["mp4", "mov", "mkv", "avi", "webm", "m4v"]
            case .archives:
                return ["zip", "rar", "7z", "tar", "gz", "dmg", "pkg", "iso"]
            }
        }
    }

    struct RootRow: Identifiable {
        let root: IndexRoot
        let state: IndexRootState
        let entryCount: Int64
        let scannedCount: Int64

        var id: Int64 { root.id }
        var displayName: String { (root.path as NSString).abbreviatingWithTildeInPath }
    }

    /// Problema de acceso a una carpeta de la app (p. ej. TCC de macOS sin permiso):
    /// la UI ofrece abrir Ajustes del Sistema y reintentar.
    struct AccessIssue: Equatable {
        let folderPath: String
    }

    // MARK: - Estado publicado

    @Published var query: String = "" {
        didSet { scheduleSearch() }
    }
    @Published var selectedKind: ResultKindFilter = .all {
        didSet { scheduleSearch() }
    }
    @Published var directoriesOnly: Bool = false {
        didSet { scheduleSearch() }
    }
    /// Busca también dentro del texto extraído de los documentos archivados (F7.5).
    @Published var searchInContent: Bool = UserDefaults.standard.bool(forKey: SearchViewModel.contentSearchDefaultsKey) {
        didSet {
            UserDefaults.standard.set(searchInContent, forKey: SearchViewModel.contentSearchDefaultsKey)
            scheduleSearch()
        }
    }
    @Published var selectedRootID: Int64? {
        didSet { scheduleSearch() }
    }
    @Published var selection: Int64?
    @Published private(set) var hits: [IndexSearchHit] = []
    @Published private(set) var isSearching = false
    @Published private(set) var roots: [RootRow] = []
    @Published var lastErrorMessage: String?
    @Published private(set) var filingRootPath: String? = FilingConfiguration.rootPath
    @Published private(set) var sourceFolderPaths: [String] = FilingConfiguration.sourcePaths
    /// Primera carpeta de entrada (compatibilidad con onboarding y textos).
    var sourceFolderPath: String? { sourceFolderPaths.first }
    @Published private(set) var organizationPaused = FilingConfiguration.organizationPaused
    @Published var simulationMode: Bool = FilingConfiguration.simulationMode {
        didSet {
            FilingConfiguration.simulationMode = simulationMode
            coordinator?.simulationMode = simulationMode
            J4Log.info(.app, simulationMode ? "Modo simulación activado (no se moverá nada)." : "Modo simulación desactivado (archivado real).")
            postFilingConfigChanged()
        }
    }
    @Published var showActivity = false
    @Published private(set) var activityEntries: [JournalEntry] = []
    @Published private(set) var organizedTodayCount = 0
    /// Elementos pendientes en la sin clasificar (para la bandeja de «Inicio», G1).
    @Published private(set) var quarantineCount = 0
    /// G2 — sugerencias proactivas (tarjeta de «Inicio»): detectores baratos sobre el índice y
    /// las carpetas de entrada. Nada se ejecuta sin confirmación.
    @Published private(set) var suggestions: [ProactiveSuggestion] = []
    /// Progreso mientras se aplica una sugerencia («Verificando duplicados… 3/12»).
    @Published private(set) var suggestionsBusy: String?
    @Published var lastOutcomeMessage: String?
    @Published var showInitialSetup = false
    @Published var accessIssue: AccessIssue?

    /// Arranque idempotente (G1): «Inicio» y «Buscar» comparten el mismo modelo.
    private var hasStarted = false

    // MARK: - Derivados

    var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var highlightTerms: [String] {
        trimmedQuery.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    var totalIndexedEntries: Int64 {
        roots.reduce(0) { $0 + $1.entryCount }
    }

    var indexingLabel: String? {
        let crawling = roots.filter { $0.state == .crawling }
        guard !crawling.isEmpty else { return nil }
        let scanned = crawling.reduce(Int64(0)) { $0 + $1.scannedCount }
        return "Indexando… \(scanned) entradas escaneadas"
    }

    var selectedHit: IndexSearchHit? {
        guard let selection else { return nil }
        return hits.first { $0.entry.id == selection }
    }

    // MARK: - Privado

    private let index = SearchIndex.shared
    private let crawler: IndexCrawler
    private var searchTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?
    private var crawlTasks: [Int64: Task<Void, Never>] = [:]
    private var watchers: [Int64: IndexWatchService] = [:]
    private var sourceWatchers: [String: SourceFolderWatcher] = [:]
    private var coordinator: FilingCoordinator?
    private var pipeline: FilingPipeline?
    private var notificationObservers: [NSObjectProtocol] = []
    private let suggestionDismissals = SuggestionDismissals()
    private var suggestionsScanning = false
    private var lastSuggestionScan = Date.distantPast

    init() {
        crawler = IndexCrawler(index: SearchIndex.shared)
    }

    deinit {
        searchTask?.cancel()
        statusTask?.cancel()
        for task in crawlTasks.values {
            task.cancel()
        }
        for watcher in watchers.values {
            watcher.stopAll()
        }
        for watcher in sourceWatchers.values {
            watcher.stop()
        }
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Ciclo de vida

    func start() async {
        // «Inicio» y «Buscar» comparten este modelo: solo el primer arranque hace el trabajo.
        guard !hasStarted else { return }
        hasStarted = true
        // Renombrado JUST4INDEX → JUST4DESK (25-sep): copia preferencias y datos locales una vez.
        // OJO: la configuración se cachea en las propiedades al crear el modelo (antes de que
        // corra la migración), así que tras migrar hay que releerla — si no, la app arrancaría
        // como si fuese una instalación nueva (asistente de primer arranque incluido).
        if RenameMigration.runIfNeeded() {
            filingRootPath = FilingConfiguration.rootPath
            sourceFolderPaths = FilingConfiguration.sourcePaths
            organizationPaused = FilingConfiguration.organizationPaused
            simulationMode = FilingConfiguration.simulationMode
            searchInContent = UserDefaults.standard.bool(forKey: Self.contentSearchDefaultsKey)
            J4Log.info(.app, "Configuración releída tras la migración de datos (JUST4INDEX → JUST4DESK).")
        }
        J4Log.info(.app, "JUST4DESK \(BuildInfo.displayLabel) iniciado.")
        logOrganizationConfiguration()
        installNotificationHandlers()
        await refreshRoots()
        for row in roots where row.state == .ready {
            startWatching(rootID: row.id, path: row.root.path)
        }
        startStatusPolling()
        presentInitialSetupIfNeeded()
        setupOrganizationIfConfigured()
        await refreshActivity()
    }

    /// Deja en el registro la configuración activa al arrancar.
    private func logOrganizationConfiguration() {
        guard let root = filingRootPath, !sourceFolderPaths.isEmpty else {
            J4Log.info(.app, "Organización sin configurar todavía (se pedirá en el primer arranque).")
            return
        }
        let sources = sourceFolderPaths.map { "«\(($0 as NSString).abbreviatingWithTildeInPath)»" }.joined(separator: " + ")
        J4Log.info(.app, "Organización: entradas \(sources) → destino «\((root as NSString).abbreviatingWithTildeInPath)» · simulación: \(simulationMode ? "sí" : "no") · pausada: \(organizationPaused ? "sí" : "no")")
    }

    // MARK: - Puente con Ajustes y comandos de menú

    /// Escucha las peticiones de la ventana de Ajustes (y de los comandos de menú).
    private func installNotificationHandlers() {
        guard notificationObservers.isEmpty else { return }
        let center = NotificationCenter.default
        func observe(_ name: Notification.Name, _ handler: @escaping (Notification) -> Void) {
            notificationObservers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { notification in
                    handler(notification)
                }
            )
        }
        observe(.j4iSetSimulationMode) { [weak self] note in
            guard let value = note.object as? Bool else { return }
            Task { @MainActor [weak self] in
                guard let self, self.simulationMode != value else { return }
                self.simulationMode = value
            }
        }
        observe(.j4iSetPaused) { [weak self] note in
            guard let value = note.object as? Bool else { return }
            Task { @MainActor [weak self] in
                guard let self, self.organizationPaused != value else { return }
                self.toggleOrganizationPaused()
            }
        }
        observe(.j4iSetAIEnabled) { [weak self] note in
            guard let value = note.object as? Bool else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                AIControlCenter.shared.isEnabled = value
                J4Log.info(.ai, value ? "IA activada desde Ajustes." : "IA desactivada desde Ajustes: solo reglas locales.")
                self.postFilingConfigChanged()
            }
        }
        observe(.j4iSetAIDailyLimit) { [weak self] note in
            guard let value = note.object as? Int else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                AIControlCenter.shared.dailyLimit = value
                J4Log.info(.ai, "Límite diario de IA actualizado: \(value) llamada(s).")
                self.postFilingConfigChanged()
            }
        }
        observe(.j4iSetFilingRoot) { [weak self] note in
            guard let path = note.object as? String else { return }
            Task { @MainActor [weak self] in self?.applyFilingRootChange(to: path) }
        }
        observe(.j4iSetSourceFolder) { [weak self] note in
            guard let path = note.object as? String else { return }
            Task { @MainActor [weak self] in self?.addSourceFolder(path) }
        }
        observe(.j4iAddSourceFolder) { [weak self] note in
            guard let path = note.object as? String else { return }
            Task { @MainActor [weak self] in self?.addSourceFolder(path) }
        }
        observe(.j4iRemoveSourceFolder) { [weak self] note in
            guard let path = note.object as? String else { return }
            Task { @MainActor [weak self] in self?.removeSourceFolder(path) }
        }
        observe(.j4iRequestAddRoot) { [weak self] _ in
            Task { @MainActor [weak self] in self?.addRootViaPanel() }
        }
        observe(.j4iRequestRootReindex) { [weak self] note in
            guard let rootID = note.object as? Int64 else { return }
            Task { @MainActor [weak self] in
                guard let self, let row = self.roots.first(where: { $0.id == rootID }) else { return }
                self.reindex(row)
            }
        }
        observe(.j4iRequestRootRemoval) { [weak self] note in
            guard let rootID = note.object as? Int64 else { return }
            Task { @MainActor [weak self] in
                guard let self, let row = self.roots.first(where: { $0.id == rootID }) else { return }
                self.removeRoot(row)
            }
        }
        observe(.j4iIngestFiles) { [weak self] note in
            guard let files = note.object as? [URL], !files.isEmpty else { return }
            Task { @MainActor [weak self] in
                self?.ingestSentFiles(files)
            }
        }
    }

    private func postFilingConfigChanged() {
        NotificationCenter.default.post(name: .j4iFilingConfigChanged, object: nil)
    }

    /// Aplica una nueva carpeta raíz de organización (desde Ajustes).
    func applyFilingRootChange(to path: String) {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        guard standardized != filingRootPath else { return }
        filingRootPath = standardized
        FilingConfiguration.rootPath = standardized
        J4Log.info(.app, "Carpeta de organización cambiada a «\(standardized)».")
        postFilingConfigChanged()
        Task {
            syncTaxonomy(rootPath: standardized)
            if let root = try? await index.addRoot(path: standardized) {
                await refreshRoots()
                startCrawl(rootID: root.id, path: root.path, fullReindex: false)
            }
            configureCoordinator()
            postFilingConfigChanged()
        }
    }

    /// Añade una carpeta de entrada vigilada (N4: pueden coexistir varias).
    func addSourceFolder(_ path: String) {
        let updated = FilingConfiguration.adding(path, to: sourceFolderPaths)
        guard updated != sourceFolderPaths else { return }
        let standardized = updated.last ?? path
        sourceFolderPaths = updated
        FilingConfiguration.sourcePaths = updated
        J4Log.info(.app, "Carpeta de entrada añadida: «\((standardized as NSString).abbreviatingWithTildeInPath)».")
        startSourceWatchersIfNeeded()
        postFilingConfigChanged()
    }

    /// Quita una carpeta de entrada (deja de vigilarse; lo ya archivado no se toca).
    func removeSourceFolder(_ path: String) {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        let updated = FilingConfiguration.removing(standardized, from: sourceFolderPaths)
        guard updated != sourceFolderPaths else { return }
        sourceWatchers[standardized]?.stop()
        sourceWatchers.removeValue(forKey: standardized)
        sourceFolderPaths = updated
        FilingConfiguration.sourcePaths = updated
        J4Log.info(.app, "Carpeta de entrada quitada: «\((standardized as NSString).abbreviatingWithTildeInPath)».")
        postFilingConfigChanged()
    }

    // MARK: - Configuración inicial (organización de documentos)

    func presentInitialSetupIfNeeded() {
        if filingRootPath == nil {
            showInitialSetup = true
        }
    }

    func completeInitialSetup(rootPath: String, sourcePath: String) {
        FilingConfiguration.rootPath = rootPath
        let updatedSources = FilingConfiguration.adding(sourcePath, to: sourceFolderPaths)
        sourceFolderPaths = updatedSources
        FilingConfiguration.sourcePaths = updatedSources
        filingRootPath = rootPath
        showInitialSetup = false
        J4Log.info(.app, "Configuración inicial completada: raíz «\(rootPath)», entrada «\(sourcePath)».")
        Task {
            if let root = try? await index.addRoot(path: rootPath) {
                await refreshRoots()
                startCrawl(rootID: root.id, path: root.path, fullReindex: false)
            }
        }
        setupOrganizationIfConfigured()
        postFilingConfigChanged()
    }

    func reconfigureFilingRoot() {
        showInitialSetup = true
    }

    // MARK: - Organización (archivado automático)

    private func setupOrganizationIfConfigured() {
        guard let rootPath = filingRootPath, !sourceFolderPaths.isEmpty else { return }
        syncTaxonomy(rootPath: rootPath)
        configureCoordinator()
        startSourceWatchersIfNeeded()
    }

    /// Instala/actualiza el esqueleto de taxonomía (idempotente): las categorías nuevas
    /// (p. ej. `12_Software`, `13_Multimedia`) aparecen también en instalaciones existentes.
    private func syncTaxonomy(rootPath: String) {
        let report = TaxonomyInstaller.install(at: URL(fileURLWithPath: rootPath, isDirectory: true))
        if !report.created.isEmpty {
            J4Log.info(.app, "Taxonomía actualizada: \(report.created.count) carpeta(s) nueva(s) (\(report.created.joined(separator: ", "))).")
        }
        if !report.conflicts.isEmpty {
            J4Log.warn(.app, "Conflictos al crear carpetas de taxonomía: \(report.conflicts.joined(separator: ", ")).")
        }
    }

    private func configureCoordinator() {
        guard let rootPath = filingRootPath else { return }
        let advisor = DeepSeekFilingAdvisor()   // nil si no hay API key → solo reglas locales
        J4Log.info(.ai, advisor != nil
            ? "Clave de DeepSeek detectada: clasificación con IA activada."
            : "Sin clave de DeepSeek: clasificación solo con reglas locales.")
        J4Log.info(.ai, "Skill de clasificación v\(FilingSkill.version) — \(FilingSkill.curatedCases.count) caso(s) curado(s).")
        let aiUsage = AIControlCenter.shared.usage()
        J4Log.info(.ai, "Control IA: \(aiUsage.isEnabled ? "activada" : "desactivada") · llamadas hoy \(aiUsage.callsToday)/\(aiUsage.dailyLimit) · total \(aiUsage.callsTotal) · tokens hoy \(aiUsage.tokensToday) · total \(aiUsage.tokensTotal).")
        let knowledgeStats = LocalKnowledgeStore.shared.stats()
        J4Log.info(.ai, "Conocimiento local: \(knowledgeStats.promotedCount) regla(s) promovida(s) · \(knowledgeStats.learnedEntries) característica(s) observada(s) · aplicadas hoy \(knowledgeStats.appliedToday).")
        let coord = FilingCoordinator(
            index: index,
            rootURL: URL(fileURLWithPath: rootPath, isDirectory: true),
            simulationMode: simulationMode,
            advisor: advisor
        )
        coordinator = coord
        pipeline = FilingPipeline(coordinator: coord)
    }

    /// Arranca (idempotente) una vigilancia por cada carpeta de entrada configurada (N4).
    private func startSourceWatchersIfNeeded() {
        guard !organizationPaused, !sourceFolderPaths.isEmpty else { return }
        var failures: [String] = []
        for path in sourceFolderPaths {
            let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
            guard sourceWatchers[standardized] == nil else { continue }
            let watcher = SourceFolderWatcher()
            do {
                try watcher.start(folder: URL(fileURLWithPath: standardized, isDirectory: true)) { [weak self] url in
                    Task { @MainActor [weak self] in
                        await self?.handleIncomingFile(url)
                    }
                }
                sourceWatchers[standardized] = watcher
            } catch {
                failures.append(standardized)
                lastErrorMessage = error.localizedDescription
                J4Log.error(.ingest, "No se pudo vigilar la carpeta de entrada «\((standardized as NSString).abbreviatingWithTildeInPath)»: \(error.localizedDescription)")
            }
        }
        if let first = failures.first {
            accessIssue = AccessIssue(folderPath: first)
        } else {
            accessIssue = nil
        }
    }

    /// Reintenta arrancar la vigilancia (botón «Reintentar» del aviso de permisos).
    func retrySourceAccess() {
        accessIssue = nil
        lastErrorMessage = nil
        startSourceWatchersIfNeeded()
    }

    /// Abre el panel de Privacidad adecuado para la carpeta con problema de acceso.
    func openPrivacySettings() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?\(Self.privacyAnchor(forFolder: accessIssue?.folderPath))"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    nonisolated static func privacyAnchor(forFolder path: String?) -> String {
        guard let path else { return "Privacy_AllFiles" }
        if path.hasSuffix("/Downloads") { return "Privacy_DownloadsFolder" }
        if path.hasSuffix("/Desktop") { return "Privacy_DesktopFolder" }
        if path.hasSuffix("/Documents") { return "Privacy_DocumentsFolder" }
        return "Privacy_AllFiles"
    }

    private func handleIncomingFile(_ url: URL) async {
        guard !organizationPaused, let pipeline else { return }
        J4Log.debug(.ingest, "Unidad estable detectada: «\(url.lastPathComponent)».")
        let outcome = await pipeline.processItem(url)
        lastOutcomeMessage = Self.outcomeMessage(for: outcome)
        await refreshActivity()
    }

    private static func outcomeMessage(for outcome: FilingCoordinator.Outcome) -> String {
        let name = (outcome.sourcePath as NSString).lastPathComponent
        switch outcome.action {
        case "move":
            return "Archivado: \(name) → \(outcome.categoryPath)"
        case "quarantine":
            return "Por revisar: \(name)"
        case "simulate":
            return "Simulación: \(name) → \(outcome.categoryPath)"
        case "skipped-duplicate":
            return "Duplicado: \(name) (dejado en origen)"
        case "skipped-empty":
            return "Carpeta vacía: \(name) (dejada en origen)"
        default:
            return "Error con \(name): \(outcome.reason)"
        }
    }

    func toggleOrganizationPaused() {
        organizationPaused.toggle()
        FilingConfiguration.organizationPaused = organizationPaused
        if organizationPaused {
            for watcher in sourceWatchers.values {
                watcher.stop()
            }
            sourceWatchers = [:]
            J4Log.info(.app, "Organización pausada.")
        } else {
            J4Log.info(.app, "Organización reanudada.")
            startSourceWatchersIfNeeded()
        }
        postFilingConfigChanged()
    }

    func refreshActivity() async {
        let entries = try? await index.journalRecent(limit: 100)
        activityEntries = entries ?? []
        let startOfDay = Calendar.current.startOfDay(for: Date())
        organizedTodayCount = activityEntries.filter { $0.action == "move" && $0.timestamp >= startOfDay }.count
        await refreshQuarantineCount()
        await refreshSuggestions()
    }

    /// Cuenta los elementos de la sin clasificar (listado plano y barato) para la bandeja de «Inicio».
    /// Usa el MISMO criterio que la ventana «Por revisar» (`QuarantineListing`): los ocultos no
    /// cuentan (un `.DS_Store` creado por Finder llegó a mostrarse como «1 elemento por revisar»).
    func refreshQuarantineCount() async {
        guard let rootPath = filingRootPath else {
            quarantineCount = 0
            return
        }
        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
        let count = await Task.detached(priority: .utility) { () -> Int in
            QuarantineListing.itemURLs(rootURL: rootURL).count
        }.value
        quarantineCount = count
    }

    // MARK: - Sugerencias proactivas (G2)

    /// Re-escanea las sugerencias proactivas: listados de primer nivel de las carpetas de entrada
    /// (más el Escritorio) y dos consultas al índice. Sin hash aquí (eso ocurre al aplicar
    /// duplicados). Limitado a un escaneo cada 60 s salvo que se fuerce (al aplicar incluido).
    func refreshSuggestions(force: Bool = false) async {
        guard !suggestionsScanning else { return }
        guard force || Date().timeIntervalSince(lastSuggestionScan) > 60 else { return }
        guard filingRootPath != nil else {
            suggestions = []
            return
        }
        suggestionsScanning = true
        defer {
            suggestionsScanning = false
            lastSuggestionScan = Date()
        }

        let sourceURLs = sourceFolderPaths.map { URL(fileURLWithPath: $0, isDirectory: true) }
        let sourceLabels = sourceFolderPaths.map { ($0 as NSString).abbreviatingWithTildeInPath }
        var built: [ProactiveSuggestion] = []

        // 1) Posibles duplicados que siguen en las entradas (coinciden en tamaño con el archivo).
        let knownSizes = (try? await index.indexedFileSizes(minBytes: ProactiveSuggestionScanner.duplicateMinBytes)) ?? []
        if let duplicates = ProactiveSuggestionScanner.duplicateSuggestion(folders: sourceURLs, labels: sourceLabels, knownSizes: knownSizes) {
            built.append(duplicates)
        }

        // 2) Capturas sueltas en las entradas y en el Escritorio (donde suelen quedarse).
        var shotFolders = sourceURLs
        var shotLabels = sourceLabels
        let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: desktop.path, isDirectory: &isDirectory), isDirectory.boolValue {
            shotFolders.append(desktop)
            shotLabels.append("Escritorio")
        }
        if let screenshots = ProactiveSuggestionScanner.screenshotSuggestion(folders: shotFolders, labels: shotLabels) {
            built.append(screenshots)
        }

        // 3) Grandes y olvidados (≥1 GB sin cambios desde hace 180 días), desde el índice.
        let cutoff = Calendar.current.date(byAdding: .day, value: -ProactiveSuggestionScanner.largeForgottenDays, to: Date()) ?? Date()
        let largeEntries = (try? await index.largeFiles(minBytes: ProactiveSuggestionScanner.largeMinBytes, olderThan: cutoff, limit: 60)) ?? []
        if let large = ProactiveSuggestionScanner.largeForgottenSuggestion(entries: largeEntries) {
            built.append(large)
        }

        let now = Date()
        suggestions = built.filter { !suggestionDismissals.isDismissed($0.kind, now: now) }
        J4Log.debug(.app, "Sugerencias: \(suggestions.count) activa(s) [\(suggestions.map(\.kind.rawValue).joined(separator: ", "))]")
    }

    /// «Ahora no» (7 días) o «Nunca más»: silencia la sugerencia y la quita de la tarjeta.
    func snoozeSuggestion(_ kind: ProactiveSuggestionKind, forever: Bool) {
        suggestionDismissals.snooze(kind, forever: forever, now: Date())
        J4Log.info(.app, forever
            ? "Sugerencia «\(kind.rawValue)» silenciada para siempre."
            : "Sugerencia «\(kind.rawValue)» pospuesta 7 días.")
        suggestions.removeAll { $0.kind == kind }
    }

    /// Revela en el Finder los primeros elementos de una sugerencia (p. ej. grandes y olvidados).
    func revealSuggestionItems(_ suggestion: ProactiveSuggestion) {
        let urls = suggestion.items.prefix(10).map { URL(fileURLWithPath: $0.path) }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    /// Aplica una sugerencia (la confirmación la da la UI antes):
    /// - duplicados → verificación por hash + Papelera (reversible);
    /// - capturas → archivado real con journal/undo, aunque la simulación esté activa
    ///   (acción manual y explícita, igual que «Por revisar»);
    /// - grandes y olvidados → solo revela en Finder (el archivo en frío llega en una fase futura).
    func applySuggestion(_ suggestion: ProactiveSuggestion) {
        switch suggestion.kind {
        case .duplicates:
            Task { await cleanDuplicates(suggestion) }
        case .screenshots:
            Task { await fileScreenshots(suggestion) }
        case .largeForgotten:
            revealSuggestionItems(suggestion)
        }
    }

    private func cleanDuplicates(_ suggestion: ProactiveSuggestion) async {
        suggestionsBusy = "Verificando duplicados…"
        var trashed = 0
        var freedBytes: Int64 = 0
        var skipped = 0
        var failed = 0
        for (position, item) in suggestion.items.enumerated() {
            suggestionsBusy = "Verificando duplicados… \(position + 1)/\(suggestion.items.count)"
            let url = URL(fileURLWithPath: item.path)
            let hash = await Task.detached(priority: .utility) { DocumentAnalyzer.sha256Hex(of: url) }.value
            guard let hash else {
                failed += 1
                continue
            }
            let cached = try? await index.loadCachedAnalysis(hash: hash)
            if let filedPath = cached?.filedPath, !filedPath.isEmpty, FileManager.default.fileExists(atPath: filedPath) {
                do {
                    try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                    trashed += 1
                    freedBytes += item.sizeBytes
                    J4Log.info(.filing, "Duplicado ya archivado en «\((filedPath as NSString).abbreviatingWithTildeInPath)»: «\(item.name)» a la Papelera.")
                } catch {
                    failed += 1
                    J4Log.warn(.filing, "No se pudo mover a la Papelera «\(item.name)»: \(error.localizedDescription)")
                }
            } else {
                skipped += 1
            }
        }
        var message = "Duplicados: \(trashed) a la Papelera (\(ByteCountFormatter.string(fromByteCount: freedBytes, countStyle: .file)))"
        if skipped > 0 { message += " · \(skipped) ya no eran duplicados" }
        if failed > 0 { message += " · \(failed) con error" }
        lastOutcomeMessage = message
        J4Log.info(.app, message)
        suggestionsBusy = nil
        await refreshActivity()
        await refreshSuggestions(force: true)
    }

    private func fileScreenshots(_ suggestion: ProactiveSuggestion) async {
        guard let rootPath = filingRootPath else { return }
        suggestionsBusy = "Archivando capturas…"
        let coordinator = FilingCoordinator(
            index: index,
            rootURL: URL(fileURLWithPath: rootPath, isDirectory: true),
            simulationMode: false,
            advisor: DeepSeekFilingAdvisor()
        )
        var moved = 0
        var quarantined = 0
        var skipped = 0
        for (position, item) in suggestion.items.enumerated() {
            suggestionsBusy = "Archivando capturas… \(position + 1)/\(suggestion.items.count)"
            let outcome = await coordinator.processItem(at: URL(fileURLWithPath: item.path))
            switch outcome.action {
            case "move": moved += 1
            case "quarantine": quarantined += 1
            default: skipped += 1
            }
        }
        var message = "Capturas: \(moved) archivada(s)"
        if quarantined > 0 { message += " · \(quarantined) por revisar" }
        if skipped > 0 { message += " · \(skipped) omitida(s)" }
        lastOutcomeMessage = message
        J4Log.info(.filing, message)
        suggestionsBusy = nil
        await refreshActivity()
        await refreshSuggestions(force: true)
    }

    // MARK: - Envío desde Finder (G4)

    /// «Enviar a JUST4DESK» (drop en el icono del Dock o soltar en Inicio): procesa cada elemento
    /// por el pipeline (journal + undo). Es una acción manual: no la frena la pausa, pero respeta
    /// el modo simulación configurado.
    func ingestSentFiles(_ urls: [URL]) {
        Task { await performSentIngest(urls) }
    }

    private func performSentIngest(_ urls: [URL]) async {
        guard let pipeline else {
            lastErrorMessage = "La organización no está configurada todavía."
            return
        }
        var moved = 0
        var quarantined = 0
        var skipped = 0
        var failed = 0
        for url in urls where url.isFileURL {
            let outcome = await pipeline.processItem(url)
            switch outcome.action {
            case "move": moved += 1
            case "quarantine": quarantined += 1
            case "error": failed += 1
            default: skipped += 1
            }
        }
        var message = "Enviados: \(moved) archivado(s)"
        if quarantined > 0 { message += " · \(quarantined) por revisar" }
        if skipped > 0 { message += " · \(skipped) omitido(s)" }
        if failed > 0 { message += " · \(failed) con error" }
        lastOutcomeMessage = message
        J4Log.info(.app, message)
        await refreshActivity()
    }

    func undo(entry: JournalEntry) {
        guard let coordinator else { return }
        Task {
            let undone = await coordinator.undo(entry: entry)
            if !undone {
                lastErrorMessage = "No se pudo deshacer: el fichero archivado ya no existe o la ruta original está ocupada."
            }
            await refreshActivity()
        }
    }

    func undoLast() {
        if let last = activityEntries.first(where: { $0.isUndoable }) {
            undo(entry: last)
        }
    }

    func revealQuarantine() {
        guard let rootPath = filingRootPath else { return }
        let quarantine = URL(fileURLWithPath: rootPath, isDirectory: true)
            .appendingPathComponent(DefaultTaxonomy.quarantineRelativePath, isDirectory: true)
        guard FileManager.default.fileExists(atPath: quarantine.path) else {
            lastErrorMessage = "Todavía no existe la carpeta sin clasificar."
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([quarantine])
    }

    func revealPath(_ path: String) {
        guard FileManager.default.fileExists(atPath: path) else {
            lastErrorMessage = "La ruta ya no existe: \(path)"
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    var organizationStatusLabel: String? {
        guard let root = filingRootPath else { return nil }
        var label = (root as NSString).abbreviatingWithTildeInPath
        var tags: [String] = []
        if organizationPaused { tags.append("pausada") }
        if simulationMode { tags.append("simulación") }
        if !tags.isEmpty { label += " (\(tags.joined(separator: ", ")))" }
        if organizedTodayCount > 0 { label += " · \(organizedTodayCount) hoy" }
        return label
    }

    // MARK: - Búsqueda (debounce + cancelación)

    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard let self, !Task.isCancelled else { return }
            await self.performSearch()
        }
    }

    private func performSearch() async {
        let term = trimmedQuery
        guard !term.isEmpty else {
            hits = []
            isSearching = false
            return
        }

        isSearching = true
        var filters = IndexSearchFilters()
        filters.rootID = selectedRootID
        filters.extensions = selectedKind.extensions
        filters.directoriesOnly = directoriesOnly ? true : nil
        let request = IndexSearchRequest(query: term, filters: filters, limit: 300, includeContent: searchInContent)
        let started = Date()

        do {
            let results = try await index.search(request)
            guard !Task.isCancelled else { return }
            hits = results
            let mode = searchInContent ? " (con contenido)" : ""
            J4Log.debug(.search, "«\(term)»\(mode) → \(results.count) resultado(s) en \(Int(Date().timeIntervalSince(started) * 1000)) ms.")
            if let current = selection, !results.contains(where: { $0.entry.id == current }) {
                selection = nil
            }
        } catch {
            guard !Task.isCancelled else { return }
            hits = []
            lastErrorMessage = error.localizedDescription
            J4Log.error(.search, "La búsqueda «\(term)» falló: \(error.localizedDescription)")
        }
        isSearching = false
    }

    // MARK: - Raíces e indexación

    func refreshRoots() async {
        do {
            let all = try await index.allRoots()
            var rows: [RootRow] = []
            for root in all {
                let status = try? await index.rootStatus(id: root.id)
                rows.append(
                    RootRow(
                        root: root,
                        state: status?.state ?? .pending,
                        entryCount: status?.entryCount ?? 0,
                        scannedCount: status?.scannedCount ?? 0
                    )
                )
            }
            roots = rows
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func addRootViaPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Indexar carpeta"
        panel.message = "Elige la carpeta que quieres indexar para búsqueda instantánea"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await addRoot(path: url.path) }
    }

    func addRoot(path: String) async {
        do {
            let root = try await index.addRoot(path: path)
            J4Log.info(.index, "Carpeta añadida al índice: «\((path as NSString).abbreviatingWithTildeInPath)».")
            await refreshRoots()
            startCrawl(rootID: root.id, path: root.path, fullReindex: false)
        } catch {
            lastErrorMessage = error.localizedDescription
            J4Log.error(.index, "No se pudo añadir «\(path)» al índice: \(error.localizedDescription)")
        }
    }

    func reindex(_ row: RootRow) {
        startCrawl(rootID: row.id, path: row.root.path, fullReindex: true)
    }

    func removeRoot(_ row: RootRow) {
        watchers[row.id]?.stopAll()
        watchers[row.id] = nil
        crawlTasks[row.id]?.cancel()
        crawlTasks[row.id] = nil
        Task {
            do {
                try await index.removeRoot(id: row.id)
                J4Log.info(.index, "Carpeta quitada del índice: «\(row.displayName)».")
            } catch {
                lastErrorMessage = error.localizedDescription
                J4Log.error(.index, "No se pudo quitar «\(row.root.path)» del índice: \(error.localizedDescription)")
            }
            if selectedRootID == row.id {
                selectedRootID = nil
            }
            await refreshRoots()
        }
    }

    private func startCrawl(rootID: Int64, path: String, fullReindex: Bool) {
        crawlTasks[rootID]?.cancel()
        let crawler = self.crawler
        crawlTasks[rootID] = Task { [weak self] in
            do {
                if fullReindex {
                    _ = try await crawler.reindex(rootID: rootID, rootPath: path)
                } else {
                    _ = try await crawler.crawl(rootID: rootID, rootPath: path)
                }
            } catch is CancellationError {
                // El estado real queda reflejado por el refresh siguiente.
            } catch {
                if let self {
                    self.lastErrorMessage = error.localizedDescription
                }
            }
            guard let self else { return }
            await self.refreshRoots()
            if !Task.isCancelled {
                self.startWatching(rootID: rootID, path: path)
            }
        }
    }

    private func startWatching(rootID: Int64, path: String) {
        guard watchers[rootID] == nil else { return }
        let watcher = IndexWatchService(index: index) { [weak self] rootID, rootPath in
            Task { @MainActor [weak self] in
                self?.startCrawl(rootID: rootID, path: rootPath, fullReindex: true)
            }
        }
        watchers[rootID] = watcher
        Task {
            do {
                try await watcher.startWatching(rootID: rootID, rootPath: path)
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }
    }

    private func startStatusPolling() {
        statusTask?.cancel()
        statusTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                await self.refreshRoots()
            }
        }
    }

    // MARK: - Acciones sobre resultados

    func open(_ hit: IndexSearchHit) {
        guard FileManager.default.fileExists(atPath: hit.entry.path) else {
            lastErrorMessage = "El archivo ya no existe en esa ruta. Prueba a reindexar la carpeta."
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: hit.entry.path))
    }

    func reveal(_ hit: IndexSearchHit) {
        guard FileManager.default.fileExists(atPath: hit.entry.path) else {
            lastErrorMessage = "El archivo ya no existe en esa ruta. Prueba a reindexar la carpeta."
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: hit.entry.path)])
    }

    func copyPath(_ hit: IndexSearchHit) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(hit.entry.path, forType: .string)
    }

    func openSelectedOrFirst() {
        if let selectedHit {
            open(selectedHit)
        } else if let first = hits.first {
            open(first)
        }
    }

    func revealSelected() {
        if let selectedHit {
            reveal(selectedHit)
        }
    }

    func copySelectedPath() {
        if let selectedHit {
            copyPath(selectedHit)
        }
    }
}
