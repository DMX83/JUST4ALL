import AppKit
import SwiftUI
import J4ICore
import J4IIndex

/// Ventana principal (F2): buscador instantáneo conectado al índice.
///
/// Keyboard-first: campo con foco al arrancar, flechas para navegar la lista,
/// Enter para abrir (desde el campo o desde la lista), acciones en menú contextual
/// y en la barra inferior.
struct ContentView: View {
    @StateObject private var viewModel = SearchViewModel()
    @State private var showLogViewer = false
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            filterBar
            Divider()
            results
            Divider()
            statusBar
        }
        .frame(minWidth: 860, minHeight: 560)
        .task {
            await viewModel.start()
            searchFocused = true
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
        .onReceive(NotificationCenter.default.publisher(for: .j4iShowLogViewer)) { _ in
            showLogViewer = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .j4iOpenExplorer)) { _ in
            openWindow(id: "explorer")
        }
        .onReceive(NotificationCenter.default.publisher(for: .j4iOpenReview)) { _ in
            openWindow(id: "review")
        }
        .onReceive(NotificationCenter.default.publisher(for: .j4iRequestOpenSettings)) { _ in
            J4Log.debug(.app, "Ajustes: abiertos vía SwiftUI (openSettings).")
            openSettings()
        }
    }

    // MARK: - Cabecera (campo de búsqueda)

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(searchFocused || !viewModel.trimmedQuery.isEmpty ? Color.accentColor : Color.secondary)
                TextField("Buscar…", text: $viewModel.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .focused($searchFocused)
                    .onSubmit { viewModel.openSelectedOrFirst() }
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
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        searchFocused ? Color.accentColor.opacity(0.65) : Color.secondary.opacity(0.22),
                        lineWidth: searchFocused ? 1.5 : 1
                    )
            )
            .shadow(color: .black.opacity(0.07), radius: 8, y: 2)
            .animation(.easeOut(duration: 0.15), value: searchFocused)

            if let label = viewModel.indexingLabel {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.mini)
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
    }

    // MARK: - Filtros

    private var filterBar: some View {
        HStack(spacing: 8) {
            ForEach(SearchViewModel.ResultKindFilter.allCases) { kind in
                kindChip(kind)
            }
            Spacer(minLength: 8)
            Toggle(isOn: $viewModel.directoriesOnly) {
                Text("Solo carpetas")
                    .font(.caption)
            }
            .toggleStyle(.checkbox)
            Toggle(isOn: $viewModel.searchInContent) {
                Text("En contenido")
                    .font(.caption)
            }
            .toggleStyle(.checkbox)
            .help("Busca también dentro del texto de los documentos archivados")
            Picker("", selection: $viewModel.selectedRootID) {
                Text("Todas las carpetas").tag(Int64?.none)
                ForEach(viewModel.roots) { row in
                    Text(row.displayName).tag(Int64?.some(row.id))
                }
            }
            .labelsHidden()
            .frame(maxWidth: 240)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    private func kindChip(_ kind: SearchViewModel.ResultKindFilter) -> some View {
        let selected = viewModel.selectedKind == kind
        return Button {
            viewModel.selectedKind = kind
        } label: {
            HStack(spacing: 5) {
                Image(systemName: kind.symbolName)
                    .font(.caption)
                Text(kind.label)
                    .font(.callout)
            }
            .foregroundStyle(selected ? Color.white : Color.primary)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(selected ? Color.accentColor : Color.secondary.opacity(0.12))
            )
            .overlay(
                Capsule().strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.18))
            )
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.12), value: selected)
        .help("Filtrar por tipo: \(kind.label)")
    }

    // MARK: - Resultados

    @ViewBuilder
    private var results: some View {
        if viewModel.roots.isEmpty {
            ContentUnavailableView {
                Label("Sin carpetas indexadas", systemImage: "folder.badge.plus")
            } description: {
                Text("Añade una carpeta (por ejemplo, tu carpeta de Descargas) para empezar a buscar al instante.")
            } actions: {
                Button("Añadir carpeta…") {
                    viewModel.addRootViaPanel()
                }
                .buttonStyle(.borderedProminent)
            }
        } else if viewModel.trimmedQuery.isEmpty {
            searchIdleState
        } else if viewModel.hits.isEmpty {
            ContentUnavailableView {
                Label(viewModel.isSearching ? "Buscando…" : "Sin resultados", systemImage: "magnifyingglass")
            } description: {
                Text("No hay coincidencias para «\(viewModel.trimmedQuery)» con los filtros actuales.")
            }
        } else {
            List(selection: $viewModel.selection) {
                ForEach(viewModel.hits, id: \.entry.id) { hit in
                    SearchResultRow(hit: hit, terms: viewModel.highlightTerms) {
                        viewModel.open(hit)
                    }
                    .tag(hit.entry.id)
                    .contextMenu {
                        Button("Abrir") { viewModel.open(hit) }
                        Button("Mostrar en Finder") { viewModel.reveal(hit) }
                        Divider()
                        Button("Copiar ruta") { viewModel.copyPath(hit) }
                    }
                }
            }
            .listStyle(.inset)
            .onKeyPress(.return) {
                viewModel.openSelectedOrFirst()
                return .handled
            }
        }
    }

    // MARK: - Estado inicial (sin búsqueda)

    private var searchIdleState: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.85), Color.accentColor.opacity(0.45)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 84, height: 84)
                    .shadow(color: Color.accentColor.opacity(0.35), radius: 14, y: 6)
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(spacing: 6) {
                Text("Búsqueda instantánea")
                    .font(.title2.weight(.semibold))
                    .fontDesign(.rounded)
                Text("Escribe para buscar por nombre o ruta en tus carpetas indexadas.\nActiva «En contenido» para buscar también dentro de los documentos.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 18) {
                KeycapBadge(keys: "⌘E", label: "Explorador")
                KeycapBadge(keys: "⌘R", label: "Por revisar")
                KeycapBadge(keys: "⌘L", label: "Registro")
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    // MARK: - Barra de estado

    private var statusBar: some View {
        HStack(spacing: 10) {
            Text("\(viewModel.hits.count) resultados")
            Text("·")
                .foregroundStyle(.tertiary)
            Text("\(viewModel.totalIndexedEntries) entradas indexadas")
            Text("·")
                .foregroundStyle(.tertiary)
            if let status = viewModel.organizationStatusLabel {
                Button {
                    viewModel.showActivity = true
                } label: {
                    Label(status, systemImage: "tray.2")
                }
                .buttonStyle(.plain)
                .help("Ver actividad de organización")
            } else {
                Text("Organización sin configurar")
                    .foregroundStyle(.orange)
            }
            if let outcome = viewModel.lastOutcomeMessage {
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(outcome)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            HStack(spacing: 4) {
                Button {
                    viewModel.copySelectedPath()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .disabled(viewModel.selectedHit == nil)
                .help("Copiar ruta del resultado seleccionado")
                Button {
                    viewModel.revealSelected()
                } label: {
                    Image(systemName: "folder")
                }
                .disabled(viewModel.selectedHit == nil)
                .help("Mostrar en Finder")
                Button {
                    viewModel.openSelectedOrFirst()
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .disabled(viewModel.hits.isEmpty)
                .help("Abrir el resultado seleccionado (Enter)")
            }
            .buttonStyle(.plain)
            Divider()
                .frame(height: 12)
            Menu {
                Button("Carpeta de organización…") {
                    viewModel.reconfigureFilingRoot()
                }
                if viewModel.filingRootPath != nil {
                    Button("Ver actividad…") {
                        viewModel.showActivity = true
                    }
                    Button(viewModel.organizationPaused ? "Reanudar organización" : "Pausar organización") {
                        viewModel.toggleOrganizationPaused()
                    }
                    Toggle("Modo simulación", isOn: $viewModel.simulationMode)
                    Button("Abrir cuarentena") {
                        viewModel.revealQuarantine()
                    }
                    Button("Revisar cuarentena… (⌘R)") {
                        openWindow(id: "review")
                    }
                    Button("Deshacer el último archivado") {
                        viewModel.undoLast()
                    }
                }
                Divider()
                Button("Abrir explorador") {
                    openWindow(id: "explorer")
                }
                Button("Ver registro…") {
                    showLogViewer = true
                }
                if let logURL = J4Log.fileURL {
                    Button("Revelar archivo de registro") {
                        NSWorkspace.shared.activateFileViewerSelecting([logURL])
                    }
                }
                SettingsLink {
                    Text("Ajustes… (⌘A)")
                }
                Divider()
                Button("Añadir carpeta…") {
                    viewModel.addRootViaPanel()
                }
                if !viewModel.roots.isEmpty {
                    Divider()
                    ForEach(viewModel.roots) { row in
                        Menu("\(row.displayName) — \(stateLabel(row.state))") {
                            Button("Reindexar") {
                                viewModel.reindex(row)
                            }
                            Button("Quitar del índice", role: .destructive) {
                                viewModel.removeRoot(row)
                            }
                        }
                    }
                }
            } label: {
                Label("Carpetas", systemImage: "folder")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Divider()
                .frame(height: 12)
            Button {
                openWindow(id: "explorer")
            } label: {
                Image(systemName: "rectangle.split.2x1")
            }
            .buttonStyle(.plain)
            .help("Explorador — navegar por la carpeta de organización (⌘E)")
            Button {
                showLogViewer = true
            } label: {
                Image(systemName: "text.alignleft")
            }
            .buttonStyle(.plain)
            .help("Registro en vivo (⌘L)")
            SettingsLink {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .help("Ajustes (⌘A)")
        }
        .controlSize(.small)
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func stateLabel(_ state: IndexRootState) -> String {
        switch state {
        case .pending: return "pendiente"
        case .crawling: return "indexando"
        case .ready: return "listo"
        case .failed: return "error"
        }
    }
}
