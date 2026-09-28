import AppKit
import SwiftUI
import J4IAI
import J4ICore
import J4IFiling
import J4IIndex

/// G1 — Pantalla «Inicio»: el centro de control de tu escritorio digital.
///
/// Sustituye al buscador como pantalla principal: resume **lo que necesita una decisión**
/// (bandeja: por revisar, deshacer, avisos), **lo que hizo la app** (actividad reciente, siempre
/// con deshacer), el **estado** (destino, índice, IA, conocimiento local) y los **accesos**
/// rápidos. El buscador completo sigue disponible en la ventana «Buscar» (⌘F) y el omnibox
/// (⌘K) busca al instante desde aquí (Enter abre el primer resultado).
struct HomeView: View {
    @EnvironmentObject private var viewModel: SearchViewModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showLogViewer = false
    @State private var pendingSuggestion: ProactiveSuggestion?
    @State private var showNewCollection = false
    @State private var editingCollection: SavedCollection?
    @State private var showWeeklyReport = false
    /// G5.1 — confirmación pendiente de etiquetado Finder.
    @State private var pendingFinderTag: FinderTagRequest?

    /// G5.1 — petición de etiquetado Finder pendiente de confirmación.
    private struct FinderTagRequest: Identifiable {
        let id = UUID()
        let collection: SavedCollection
        let removing: Bool
        let fileCount: Int

        var title: String { "Etiquetas Finder — «\(collection.name)»" }

        var confirmLabel: String {
            removing
                ? "Quitar la etiqueta de \(fileCount) fichero(s)"
                : "Etiquetar \(fileCount) fichero(s)"
        }

        var message: String {
            removing
                ? "Se quitará la etiqueta «\(collection.name)» de \(fileCount) fichero(s). No se toca ni el contenido ni la ubicación."
                : "Se escribirá la etiqueta Finder «\(collection.name)» en \(fileCount) fichero(s): metadatos que viajan con el archivo (visibles en Finder y Spotlight; reversibles con «Quitar etiqueta»)."
        }
    }
    @FocusState private var omniFocused: Bool

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 400), spacing: J4I.Space.m)]
    }

    var body: some View {
        withNotificationHandlers(sheetAttachedContent)
    }

    /// Cuerpo base (con hojas, alertas y diálogos). Separado del `body` para que el
    /// type-checker no tipo-compruebe toda la cadena junta (lección de G5.1 y N7).
    private var sheetAttachedContent: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: J4I.Space.m) {
                    // G2: las sugerencias (bandeja de propuestas) van a ancho completo para no
                    // descompensar la rejilla 2×2 del centro de control.
                    suggestionsCard
                    LazyVGrid(columns: columns, alignment: .leading, spacing: J4I.Space.m) {
                        inboxCard
                        activityCard
                        statusCard
                        shortcutsCard
                        collectionsCard
                    }
                }
                .padding(J4I.Space.l)
            }
            Divider()
            footer
        }
        .frame(minWidth: 780, minHeight: 540)
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty else { return false }
            viewModel.ingestSentFiles(files)
            return true
        }
        .task {
            await viewModel.start()
            await viewModel.refreshActivity()
            omniFocused = true
        }
        .alert(
            "Ha ocurrido un problema",
            isPresented: Binding(
                get: { viewModel.lastErrorMessage != nil },
                set: { if !$0 { viewModel.lastErrorMessage = nil } }
            ),
            actions: {
                if viewModel.accessIssue != nil {
                    Button("Abrir Ajustes del Sistema…") { viewModel.openPrivacySettings() }
                    Button("Reintentar") { viewModel.retrySourceAccess() }
                }
                Button("Vale", role: .cancel) {}
            },
            message: {
                Text(viewModel.lastErrorMessage ?? "")
            }
        )
        .confirmationDialog(
            pendingSuggestion?.title ?? "",
            isPresented: Binding(
                get: { pendingSuggestion != nil },
                set: { if !$0 { pendingSuggestion = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingSuggestion
        ) { suggestion in
            Button(confirmButtonLabel(suggestion.kind)) {
                viewModel.applySuggestion(suggestion)
            }
            Button("Cancelar", role: .cancel) {}
        } message: { suggestion in
            Text(confirmMessage(for: suggestion))
        }
        .sheet(isPresented: $viewModel.showInitialSetup) {
            InitialSetupSheet(
                initialPath: viewModel.filingRootPath ?? FilingConfiguration.suggestedRootPath,
                initialSourcePath: viewModel.sourceFolderPath ?? FilingConfiguration.suggestedSourcePath
            ) { rootPath, sourcePath in
                viewModel.completeInitialSetup(rootPath: rootPath, sourcePath: sourcePath)
            }
        }
        .sheet(isPresented: $viewModel.showActivity) {
            FilingActivitySheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showLogViewer) {
            LogViewerSheet()
        }
        .sheet(isPresented: $showNewCollection) {
            CollectionEditorSheet(defaultQuery: viewModel.trimmedQuery) { name, query in
                viewModel.addCollection(name: name, query: query)
            }
        }
        .sheet(item: $editingCollection) { collection in
            CollectionEditorSheet(editing: collection) { name, query in
                viewModel.updateCollection(collection.id, name: name, query: query)
            }
        }
        .sheet(isPresented: $showWeeklyReport) {
            WeeklyReportSheet(viewModel: viewModel)
        }
    }

    /// N7 — puente de notificaciones y comandos (cada canal abre su ventana o ajusta el
    /// estado). Vive en un método aparte para no recargar `body` (límite del type-checker).
    private func withNotificationHandlers<Content: View>(_ content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .j4iShowLogViewer)) { _ in
            showLogViewer = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .j4iOpenExplorer)) { _ in
            openWindow(id: "explorer")
        }
        .onReceive(NotificationCenter.default.publisher(for: .j4iOpenReview)) { _ in
            openWindow(id: "review")
        }
        .onReceive(NotificationCenter.default.publisher(for: .j4iOpenRules)) { _ in
            openWindow(id: "rules")
        }
        .onReceive(NotificationCenter.default.publisher(for: .j4iOpenChat)) { _ in
            openWindow(id: "chat")
        }
        .onReceive(NotificationCenter.default.publisher(for: .j4iOpenStats)) { _ in
            openWindow(id: "stats")
        }
        .onReceive(NotificationCenter.default.publisher(for: .j4iOpenSearch)) { note in
            if let query = note.object as? String, !query.isEmpty {
                viewModel.query = query
            }
            openWindow(id: "search")
        }
        .onReceive(NotificationCenter.default.publisher(for: .j4iFocusOmnibox)) { _ in
            omniFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .j4iRequestOpenSettings)) { _ in
            J4Log.debug(.app, "Ajustes: abiertos vía SwiftUI (openSettings).")
            openSettings()
        }
        .onReceive(NotificationCenter.default.publisher(for: .j4iFilingConfigChanged)) { _ in
            Task { await viewModel.refreshActivity() }
        }
    }

    // MARK: - Cabecera (omnibox ⌘K)

    private var header: some View {
        VStack(alignment: .leading, spacing: J4I.Space.s) {
            HStack(spacing: 10) {
                BrandMark(size: 30)
                omnibox
                GhostIconButton(systemImage: "magnifyingglass", help: "Ventana de búsqueda (⌘F)") {
                    openWindow(id: "search")
                }
                GhostIconButton(systemImage: "rectangle.split.2x1", help: "Explorador (⌘E)") {
                    openWindow(id: "explorer")
                }
                GhostIconButton(systemImage: "tray.full", help: "Por revisar (⌘R)") {
                    openWindow(id: "review")
                }
                GhostIconButton(systemImage: "text.alignleft", help: "Registro (⌘L)") {
                    showLogViewer = true
                }
                SettingsLink {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 24, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Ajustes (⌘A)")
            }
            omniResults
        }
        .padding(.horizontal, J4I.Space.l)
        .padding(.top, J4I.Space.m)
        .padding(.bottom, J4I.Space.s)
    }

    private var omnibox: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(omniFocused || !viewModel.trimmedQuery.isEmpty ? J4I.brand : Color.secondary)
            TextField("Buscar o pedir una acción…", text: $viewModel.query)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($omniFocused)
                .onSubmit { submitOmni() }
                .onExitCommand {
                    viewModel.query = ""
                    omniFocused = false
                }
            if viewModel.isSearching {
                ProgressView()
                    .controlSize(.small)
            }
            if !viewModel.trimmedQuery.isEmpty {
                Button {
                    viewModel.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Limpiar búsqueda")
            }
            Text("⌘K")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: J4I.Radius.medium, style: .continuous)
                .fill(J4I.well)
        )
        .overlay(
            RoundedRectangle(cornerRadius: J4I.Radius.medium, style: .continuous)
                .strokeBorder(
                    omniFocused ? J4I.brand.opacity(0.75) : J4I.hairline.opacity(0.6),
                    lineWidth: omniFocused ? 1.5 : 1
                )
        )
        .shadow(color: omniFocused ? J4I.brand.opacity(0.18) : J4I.cardShadow, radius: omniFocused ? 7 : 4, y: 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: omniFocused)
    }

    /// Enter: abre el primer resultado; sin resultados, abre la ventana «Buscar».
    private func submitOmni() {
        if let first = viewModel.hits.first {
            viewModel.open(first)
        } else {
            openWindow(id: "search")
        }
    }

    /// Resultados inmediatos bajo el omnibox (los 7 primeros + «ver todos»).
    @ViewBuilder
    private var omniResults: some View {
        if omniFocused, !viewModel.trimmedQuery.isEmpty,
           (!viewModel.hits.isEmpty || !matchingCollections.isEmpty) {
            if let match = matchingCollections.first {
                collectionOmniRow(match)
            }
            if !viewModel.hits.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(viewModel.hits.prefix(7), id: \.entry.id) { hit in
                    Button {
                        viewModel.open(hit)
                    } label: {
                        HStack(spacing: 8) {
                            Image(nsImage: ResultIconCache.icon(for: hit.entry))
                                .resizable()
                                .frame(width: 18, height: 18)
                            Text(hit.entry.name)
                                .font(.system(size: 12.5))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 8)
                            Text((hit.entry.path as NSString).abbreviatingWithTildeInPath)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverHighlight(cornerRadius: J4I.Radius.small, intensity: 0.06)
                }
                Divider()
                    .padding(.vertical, 2)
                Button {
                    openWindow(id: "search")
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.system(size: 11))
                        Text("Ver todos los resultados (\(viewModel.hits.count))")
                            .font(.system(size: 12))
                        Spacer(minLength: 8)
                        Text("⌘F")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverHighlight(cornerRadius: J4I.Radius.small, intensity: 0.06)
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: J4I.Radius.medium, style: .continuous)
                    .fill(J4I.surface)
                    .shadow(color: J4I.cardShadow, radius: 10, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: J4I.Radius.medium, style: .continuous)
                    .strokeBorder(J4I.hairline.opacity(0.6))
            )
            .padding(.leading, 40)
            }
        }
    }

    // MARK: - Bandeja

    private var undoableEntry: JournalEntry? {
        viewModel.activityEntries.first(where: { $0.isUndoable })
    }

    private var inboxCard: some View {
        J4ICard {
            VStack(alignment: .leading, spacing: J4I.Space.m) {
                cardHeader("Bandeja", "tray.full")
                quarantineRow
                Divider()
                undoRow
                if viewModel.filingRootPath == nil {
                    Divider()
                    noticeRow(
                        icon: "exclamationmark.triangle",
                        tint: J4I.warning,
                        title: "Organización sin configurar",
                        message: "Elige la carpeta raíz y las carpetas de entrada.",
                        actionTitle: "Configurar…"
                    ) {
                        viewModel.reconfigureFilingRoot()
                    }
                } else if viewModel.organizationPaused {
                    Divider()
                    noticeRow(
                        icon: "pause.circle",
                        tint: J4I.warning,
                        title: "Organización pausada",
                        message: "Los ficheros nuevos no se archivarán hasta reanudar.",
                        actionTitle: "Reanudar"
                    ) {
                        viewModel.toggleOrganizationPaused()
                    }
                }
            }
        }
    }

    // MARK: - Sugerencias (G2)

    @ViewBuilder
    private var suggestionsCard: some View {
        if !viewModel.suggestions.isEmpty || viewModel.suggestionsBusy != nil {
            J4ICard {
                VStack(alignment: .leading, spacing: J4I.Space.m) {
                    HStack(spacing: 6) {
                        cardHeader("Sugerencias", "sparkles")
                        Spacer()
                        if let busy = viewModel.suggestionsBusy {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.mini)
                                Text(busy)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    ForEach(viewModel.suggestions) { suggestion in
                        suggestionRow(suggestion)
                    }
                }
            }
        }
    }

    private func suggestionRow(_ suggestion: ProactiveSuggestion) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: suggestion.kind.symbolName)
                .font(.system(size: 15))
                .foregroundStyle(suggestionTint(suggestion.kind))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(suggestion.title)
                    .font(.system(size: 12.5, weight: .medium))
                Text("\(suggestion.items.count) elemento(s) · \(ByteCountFormatter.string(fromByteCount: suggestion.totalBytes, countStyle: .file))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(suggestion.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 680, alignment: .leading)
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(suggestion.items.prefix(3)) { item in
                        Text("· \(item.name)")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if suggestion.items.count > 3 {
                        Text("y \(suggestion.items.count - 3) más…")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
                HStack(spacing: 8) {
                    Button(primaryLabel(suggestion.kind)) {
                        primaryAction(suggestion)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    Button("Ahora no") {
                        viewModel.snoozeSuggestion(suggestion.kind, forever: false)
                    }
                    .controlSize(.small)
                    .help("Ocultar esta sugerencia durante 7 días")
                    Button("Nunca más") {
                        viewModel.snoozeSuggestion(suggestion.kind, forever: true)
                    }
                    .controlSize(.small)
                    .foregroundStyle(.secondary)
                    .help("No volver a proponer esto")
                }
                .padding(.top, 3)
            }
            Spacer(minLength: 0)
        }
    }

    private func suggestionTint(_ kind: ProactiveSuggestionKind) -> Color {
        switch kind {
        case .duplicates: return J4I.brand
        case .screenshots: return J4I.warning
        case .largeForgotten: return .secondary
        }
    }

    private func primaryLabel(_ kind: ProactiveSuggestionKind) -> String {
        switch kind {
        case .duplicates: return "Verificar y limpiar"
        case .screenshots: return "Archivar"
        case .largeForgotten: return "Archivar en frío"
        }
    }

    /// Todas las acciones que mueven algo piden confirmación previa.
    private func primaryAction(_ suggestion: ProactiveSuggestion) {
        pendingSuggestion = suggestion
    }

    private func confirmButtonLabel(_ kind: ProactiveSuggestionKind) -> String {
        switch kind {
        case .duplicates: return "Verificar y enviar a la Papelera"
        case .screenshots: return "Archivar capturas"
        case .largeForgotten: return "Mover a 90_Archivo"
        }
    }

    private func confirmMessage(for suggestion: ProactiveSuggestion) -> String {
        switch suggestion.kind {
        case .duplicates:
            return "Se calculará el hash de \(suggestion.items.count) fichero(s). Solo los duplicados reales de lo ya archivado se moverán a la Papelera (reversible desde el Finder); el resto se deja."
        case .screenshots:
            return "Se archivarán \(suggestion.items.count) captura(s) (\(ByteCountFormatter.string(fromByteCount: suggestion.totalBytes, countStyle: .file))) con deshacer. Lo dudoso quedará en «sin clasificar»."
        case .largeForgotten:
            return "Se moverán \(suggestion.items.count) elemento(s) (\(ByteCountFormatter.string(fromByteCount: suggestion.totalBytes, countStyle: .file))) a «90_Archivo/…» conservando su ruta. Deshacible desde Actividad."
        }
    }

    private var quarantineRow: some View {
        HStack(spacing: 10) {
            Image(systemName: viewModel.quarantineCount > 0 ? "questionmark.folder" : "checkmark.seal")
                .font(.system(size: 15))
                .foregroundStyle(viewModel.quarantineCount > 0 ? J4I.warning : J4I.success)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(viewModel.quarantineCount > 0
                     ? "\(viewModel.quarantineCount) elemento(s) por revisar"
                     : "Nada por revisar")
                    .font(.system(size: 12.5, weight: .medium))
                Text(viewModel.quarantineCount > 0
                     ? "No se pudieron clasificar solos: asígnales un destino"
                     : "Todo lo que llegó se clasificó")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: J4I.Space.s)
            Button("Revisar") {
                openWindow(id: "review")
            }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.quarantineCount == 0)
        }
    }

    private var undoRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 15))
                .foregroundStyle(J4I.brand)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text("Deshacer el último archivado")
                    .font(.system(size: 12.5, weight: .medium))
                Text(undoableEntry.map { "«\($0.fileName)»" } ?? "No hay ningún archivado que deshacer")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: J4I.Space.s)
            Button("Deshacer") {
                viewModel.undoLast()
            }
            .controlSize(.small)
            .disabled(undoableEntry == nil)
        }
    }

    private func noticeRow(
        icon: String,
        tint: Color,
        title: String,
        message: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: J4I.Space.s)
            Button(actionTitle, action: action)
                .controlSize(.small)
        }
    }

    // MARK: - Actividad

    private var recentActivity: [JournalEntry] {
        Array(viewModel.activityEntries.prefix(4))
    }

    private var activityCard: some View {
        J4ICard {
            VStack(alignment: .leading, spacing: J4I.Space.m) {
                HStack(spacing: 6) {
                    cardHeader("Actividad", "clock.arrow.circlepath")
                    Spacer()
                    Button("Informe") {
                        showWeeklyReport = true
                    }
                    .controlSize(.small)
                    .help("Informe semanal (local, copiable y exportable en Markdown)")
                    Button("Ver todo") {
                        viewModel.showActivity = true
                    }
                    .controlSize(.small)
                    .disabled(viewModel.activityEntries.isEmpty)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(viewModel.organizedTodayCount)")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(J4I.brand)
                    Text("archivado(s) hoy")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                if recentActivity.isEmpty {
                    Text("Sin movimientos todavía. Los documentos nuevos aparecerán aquí en cuanto se archiven.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(recentActivity) { entry in
                            activityRow(entry)
                        }
                    }
                }
            }
        }
    }

    private func activityRow(_ entry: JournalEntry) -> some View {
        HStack(spacing: 8) {
            Image(systemName: activityIcon(entry))
                .font(.system(size: 11))
                .foregroundStyle(activityTint(entry))
                .frame(width: 14)
            Text(entry.fileName)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 6)
            Text(entry.categoryPath.isEmpty ? "—" : entry.categoryPath)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(entry.timestamp, format: .dateTime.hour().minute())
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
    }

    private func activityIcon(_ entry: JournalEntry) -> String {
        switch entry.action {
        case "move": return "tray.and.arrow.down"
        case "quarantine": return "questionmark.folder"
        case "cold": return "archivebox"
        case "simulate": return "eye"
        case "skipped-duplicate": return "doc.on.doc"
        default: return "exclamationmark.triangle"
        }
    }

    private func activityTint(_ entry: JournalEntry) -> Color {
        switch entry.action {
        case "move": return J4I.success
        case "quarantine": return J4I.warning
        case "simulate": return J4I.brand
        default: return .secondary
        }
    }

    // MARK: - Estado

    private var statusCard: some View {
        J4ICard {
            VStack(alignment: .leading, spacing: J4I.Space.m) {
                HStack(spacing: 6) {
                    cardHeader("Estado", "info.circle")
                    Spacer()
                    if viewModel.simulationMode {
                        StatusPill(systemImage: "eye", title: "Simulación", tint: J4I.warning, help: "No se mueve nada: solo se registra lo que haría")
                    }
                }
                VStack(alignment: .leading, spacing: 5) {
                    statusRow("Destino", viewModel.filingRootPath.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? "Sin configurar")
                    statusRow("Entradas indexadas", viewModel.totalIndexedEntries.formatted())
                    statusRow("Carpetas de entrada", sourceListLabel)
                    statusRow("Uso de IA hoy", aiUsageLabel)
                    statusRow("Reglas aprendidas", "\(knowledgeStats.promotedCount)")
                }
                if let label = viewModel.indexingLabel {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.mini)
                        Text(label)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var sourceListLabel: String {
        let paths = viewModel.sourceFolderPaths.map { ($0 as NSString).abbreviatingWithTildeInPath }
        return paths.isEmpty ? "Sin configurar" : paths.joined(separator: " · ")
    }

    private var aiUsageLabel: String {
        let usage = AIControlCenter.shared.usage()
        guard usage.isEnabled else { return "Desactivada" }
        return "\(usage.callsToday)/\(usage.dailyLimit) · \(usage.tokensToday.formatted()) tokens"
    }

    private var knowledgeStats: LocalKnowledgeStore.Stats {
        LocalKnowledgeStore.shared.stats()
    }

    private func statusRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 118, alignment: .leading)
            Text(value)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Accesos

    private var shortcutsCard: some View {
        J4ICard {
            VStack(alignment: .leading, spacing: J4I.Space.m) {
                cardHeader("Accesos", "square.grid.2x2")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 148), spacing: 8)], spacing: 8) {
                    shortcutButton("Buscar", icon: "magnifyingglass", keys: "⌘F") {
                        openWindow(id: "search")
                    }
                    shortcutButton("Explorador", icon: "rectangle.split.2x1", keys: "⌘E") {
                        openWindow(id: "explorer")
                    }
                    shortcutButton("Por revisar", icon: "tray.full", keys: "⌘R") {
                        openWindow(id: "review")
                    }
                    shortcutButton("Actividad", icon: "clock.arrow.circlepath", keys: nil) {
                        viewModel.showActivity = true
                    }
                    shortcutButton("Registro", icon: "text.alignleft", keys: "⌘L") {
                        showLogViewer = true
                    }
                    shortcutButton("Ajustes", icon: "gearshape", keys: "⌘A") {
                        openSettings()
                    }
                    shortcutButton("Abrir destino", icon: "folder", keys: nil) {
                        if let root = viewModel.filingRootPath {
                            viewModel.revealPath(root)
                        }
                    }
                    shortcutButton("Sin clasificar", icon: "questionmark.folder", keys: nil) {
                        viewModel.revealQuarantine()
                    }
                    shortcutButton("Reglas", icon: "text.badge.checkmark", keys: "⌘G") {
                        openWindow(id: "rules")
                    }
                    shortcutButton("Chat", icon: "text.bubble", keys: "⇧⌘K") {
                        openWindow(id: "chat")
                    }
                    shortcutButton("Estadísticas", icon: "chart.bar.xaxis", keys: "⌘T") {
                        openWindow(id: "stats")
                    }
                }
            }
        }
    }

    // MARK: - Colecciones (G5)

    private var matchingCollections: [SavedCollection] {
        viewModel.matchingCollections(for: viewModel.trimmedQuery)
    }

    private var collectionsCard: some View {
        J4ICard {
            VStack(alignment: .leading, spacing: J4I.Space.m) {
                HStack(spacing: 6) {
                    cardHeader("Colecciones", "square.stack.3d.up")
                    Spacer()
                    if let busy = viewModel.tagBusy {
                        ProgressView()
                            .controlSize(.small)
                        Text(busy)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Button("Nueva") {
                        showNewCollection = true
                    }
                    .controlSize(.small)
                    .help("Guarda una búsqueda con nombre: organiza sin mover nada")
                }
                if viewModel.collections.isEmpty {
                    Text("Guarda una búsqueda como colección («Trading», «Fiscal 2026»…) y ábrela con un clic — sin mover nada. También desde «Buscar», con el marcador.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(viewModel.collections) { collection in
                            collectionRow(collection)
                        }
                    }
                }
            }
        }
        .confirmationDialog(
            pendingFinderTag?.title ?? "",
            isPresented: Binding(
                get: { pendingFinderTag != nil },
                set: { if !$0 { pendingFinderTag = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingFinderTag
        ) { request in
            Button(request.confirmLabel) {
                let collection = request.collection
                let removing = request.removing
                Task { await viewModel.applyFinderTag(to: collection, remove: removing) }
            }
            Button("Cancelar", role: .cancel) {}
        } message: { request in
            Text(request.message)
        }
    }

    private func collectionRow(_ collection: SavedCollection) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 11))
                .foregroundStyle(J4I.brand)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(collection.name)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                Text(collection.query)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(collectionCountLabel(collection))
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .help("Resultados actuales de la búsqueda guardada")
            Menu {
                Button("Etiquetar en Finder") { requestFinderTag(collection, removing: false) }
                Button("Quitar etiqueta") { requestFinderTag(collection, removing: true) }
            } label: {
                Image(systemName: "tag")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(viewModel.tagBusy != nil)
            .help("Etiquetas Finder: metadatos en los ficheros para verlos también fuera de JUST4DESK (reversible)")
            Button("Abrir") {
                openCollection(collection)
            }
            .controlSize(.small)
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Abrir") { openCollection(collection) }
            Button("Editar…") { editingCollection = collection }
            Divider()
            Button("Etiquetar en Finder") { requestFinderTag(collection, removing: false) }
            Button("Quitar etiqueta del Finder") { requestFinderTag(collection, removing: true) }
            Divider()
            Button("Borrar colección", role: .destructive) {
                viewModel.removeCollection(collection)
            }
        }
    }

    private func collectionCountLabel(_ collection: SavedCollection) -> String {
        guard let count = viewModel.collectionCounts[collection.id] else { return "…" }
        return count >= SearchViewModel.collectionCountLimit ? "\(SearchViewModel.collectionCountLimit)+" : "\(count)"
    }

    private func openCollection(_ collection: SavedCollection) {
        viewModel.query = collection.query
        openWindow(id: "search")
        J4Log.debug(.app, "Colección «\(collection.name)» → búsqueda «\(collection.query)».")
    }

    /// G5.1 — prepara (contando ficheros) la confirmación de etiquetado Finder.
    private func requestFinderTag(_ collection: SavedCollection, removing: Bool) {
        Task {
            let files = await viewModel.collectionFiles(collection)
            pendingFinderTag = FinderTagRequest(collection: collection, removing: removing, fileCount: files.count)
        }
    }

    private func collectionOmniRow(_ collection: SavedCollection) -> some View {
        Button {
            openCollection(collection)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(J4I.brand)
                Text("Colección «\(collection.name)»")
                    .font(.system(size: 12.5, weight: .medium))
                Spacer(minLength: 8)
                Text("abrir")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: J4I.Radius.small, style: .continuous)
                .fill(J4I.brand.opacity(0.10))
        )
        .padding(.leading, 40)
        .hoverHighlight(cornerRadius: J4I.Radius.small, intensity: 0.06)
    }

    private func shortcutButton(_ title: String, icon: String, keys: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(J4I.brand)
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let keys {
                    Text(keys)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: J4I.Radius.small, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: J4I.Radius.small, style: .continuous)
                    .strokeBorder(J4I.hairline.opacity(0.5))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(cornerRadius: J4I.Radius.small, intensity: 0.05)
    }

    // MARK: - Pie

    private var footer: some View {
        HStack(spacing: J4I.Space.s) {
            StatusPill(
                systemImage: viewModel.filingRootPath == nil ? "exclamationmark.triangle" : (viewModel.organizationPaused ? "pause.circle" : "tray.2"),
                title: viewModel.organizationStatusLabel ?? "Organización sin configurar",
                tint: viewModel.filingRootPath == nil ? J4I.warning : (viewModel.organizationPaused ? J4I.warning : J4I.success)
            )
            Text("·")
                .foregroundStyle(.quaternary)
            Text("\(viewModel.totalIndexedEntries) entradas indexadas")
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            if let outcome = viewModel.lastOutcomeMessage {
                Text("·")
                    .foregroundStyle(.quaternary)
                Text(outcome)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: J4I.Space.s)
            Text("⌘K buscar · ⌥Espacio desde cualquier app")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, J4I.Space.m)
        .padding(.vertical, 7)
    }

    // MARK: - Auxiliares

    private func cardHeader(_ title: String, _ icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .kerning(0.6)
                .foregroundStyle(.secondary)
        }
    }
}
