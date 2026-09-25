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
    @State private var showRootMenu = false
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                BrandMark(size: 30)
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(searchFocused || !viewModel.trimmedQuery.isEmpty ? J4I.brand : Color.secondary)
                    TextField("Buscar en tus carpetas…", text: $viewModel.query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16))
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
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: J4I.Radius.medium, style: .continuous)
                        .fill(J4I.well)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: J4I.Radius.medium, style: .continuous)
                        .strokeBorder(
                            searchFocused ? J4I.brand.opacity(0.75) : J4I.hairline.opacity(0.6),
                            lineWidth: searchFocused ? 1.5 : 1
                        )
                )
                .shadow(
                    color: searchFocused ? J4I.brand.opacity(0.18) : J4I.cardShadow,
                    radius: searchFocused ? 7 : 4,
                    y: 1
                )
                .animation(.easeOut(duration: 0.15), value: searchFocused)
            }

            if let label = viewModel.indexingLabel {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.mini)
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 40)
            }
        }
        .padding(.horizontal, J4I.Space.l)
        .padding(.top, J4I.Space.m)
        .padding(.bottom, J4I.Space.s)
    }

    // MARK: - Filtros

    private var filterBar: some View {
        HStack(spacing: J4I.Space.s) {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(SearchViewModel.ResultKindFilter.allCases) { kind in
                        Chip(
                            title: kind.label,
                            systemImage: kind.symbolName,
                            selected: viewModel.selectedKind == kind,
                            help: "Filtrar por tipo: \(kind.label)"
                        ) {
                            viewModel.selectedKind = kind
                        }
                    }
                }
                .padding(.leading, 40)
                .padding(.trailing, 14)
                .padding(.vertical, 2)
            }
            .scrollIndicators(.never)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.02),
                        .init(color: .black, location: 0.97),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            Spacer(minLength: J4I.Space.s)
            ToggleChip(
                title: "Solo carpetas",
                systemImage: "folder",
                isOn: $viewModel.directoriesOnly,
                help: "Mostrar solo carpetas en los resultados"
            )
            ToggleChip(
                title: "En contenido",
                systemImage: "text.magnifyingglass",
                isOn: $viewModel.searchInContent,
                help: "Busca también dentro del texto de los documentos archivados"
            )
            rootMenu
        }
        .padding(.horizontal, J4I.Space.l)
        .padding(.bottom, J4I.Space.m)
    }

    /// Menú de carpeta indexada con el lenguaje visual de los chips (F15.0).
    private var rootMenu: some View {
        Button {
            showRootMenu.toggle()
        } label: {
            ChipLabel(title: selectedRootTitle, systemImage: "square.stack.3d.up", showsChevron: true)
        }
        .buttonStyle(.plain)
        .help("Filtrar por carpeta indexada")
        .popover(isPresented: $showRootMenu, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 1) {
                rootMenuItem(title: "Todas las carpetas", selected: viewModel.selectedRootID == nil) {
                    viewModel.selectedRootID = nil
                    showRootMenu = false
                }
                if !viewModel.roots.isEmpty {
                    Divider()
                        .padding(.vertical, 3)
                }
                ForEach(viewModel.roots) { row in
                    rootMenuItem(title: row.displayName, selected: viewModel.selectedRootID == row.id) {
                        viewModel.selectedRootID = row.id
                        showRootMenu = false
                    }
                }
            }
            .padding(6)
            .frame(minWidth: 220)
        }
    }

    private var selectedRootTitle: String {
        guard let id = viewModel.selectedRootID,
              let row = viewModel.roots.first(where: { $0.id == id }) else {
            return "Todas las carpetas"
        }
        return row.displayName
    }

    private func rootMenuItem(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(J4I.brand)
                    .opacity(selected ? 1 : 0)
                    .frame(width: 12)
                Text(title)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(intensity: 0.06)
    }

    // MARK: - Resultados

    @ViewBuilder
    private var results: some View {
        if viewModel.roots.isEmpty {
            J4IEmptyState(
                systemImage: "folder.badge.plus",
                title: "Sin carpetas indexadas",
                message: "Añade una carpeta (por ejemplo, tu carpeta de Descargas) para empezar a buscar al instante."
            ) {
                Button("Añadir carpeta…") {
                    viewModel.addRootViaPanel()
                }
                .buttonStyle(.borderedProminent)
            }
        } else if viewModel.trimmedQuery.isEmpty {
            searchIdleState
        } else if viewModel.hits.isEmpty {
            J4IEmptyState(
                systemImage: "magnifyingglass",
                title: viewModel.isSearching ? "Buscando…" : "Sin resultados",
                message: "No hay coincidencias para «\(viewModel.trimmedQuery)» con los filtros actuales."
            )
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
        VStack(spacing: J4I.Space.l) {
            BrandMark(size: 64)
            VStack(spacing: 6) {
                Text("Búsqueda instantánea")
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                Text("Escribe para buscar por nombre o ruta en tus carpetas indexadas.\nActiva «En contenido» para buscar también dentro de los documentos.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: J4I.Space.l) {
                KeycapBadge(keys: "⌘E", label: "Explorador")
                KeycapBadge(keys: "⌘R", label: "Por revisar")
                KeycapBadge(keys: "⌘L", label: "Registro")
            }
            .padding(.top, 2)
            HStack(spacing: J4I.Space.s) {
                StatusPill(
                    systemImage: "square.stack.3d.up",
                    title: "\(viewModel.totalIndexedEntries.formatted()) entradas indexadas",
                    tint: J4I.brand
                )
                StatusPill(
                    systemImage: "folder",
                    title: "\(viewModel.roots.count) carpeta(s) de entrada",
                    tint: Color.secondary
                )
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(J4I.Space.xl)
    }

    // MARK: - Barra de estado

    private var statusBar: some View {
        HStack(spacing: J4I.Space.s) {
            Text("\(viewModel.hits.count) resultados")
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
            Text("·")
                .font(.system(size: 11))
                .foregroundStyle(.quaternary)
            Text("\(viewModel.totalIndexedEntries) entradas")
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            if let status = viewModel.organizationStatusLabel {
                StatusPill(
                    systemImage: "tray.2",
                    title: status,
                    tint: J4I.success,
                    help: "Ver actividad de organización"
                ) {
                    viewModel.showActivity = true
                }
            } else {
                StatusPill(
                    systemImage: "exclamationmark.triangle",
                    title: "Organización sin configurar",
                    tint: J4I.warning,
                    help: "Configura la carpeta de organización en Ajustes → Organización"
                )
            }
            if let outcome = viewModel.lastOutcomeMessage {
                Text(outcome)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: J4I.Space.s)
            HStack(spacing: 2) {
                GhostIconButton(
                    systemImage: "doc.on.doc",
                    help: "Copiar ruta del resultado seleccionado",
                    disabled: viewModel.selectedHit == nil
                ) {
                    viewModel.copySelectedPath()
                }
                GhostIconButton(
                    systemImage: "folder",
                    help: "Mostrar en Finder",
                    disabled: viewModel.selectedHit == nil
                ) {
                    viewModel.revealSelected()
                }
                GhostIconButton(
                    systemImage: "arrow.up.forward.app",
                    help: "Abrir el resultado seleccionado (Enter)",
                    disabled: viewModel.hits.isEmpty
                ) {
                    viewModel.openSelectedOrFirst()
                }
            }
            ToolbarSeparator()
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
            .controlSize(.small)
            .menuStyle(.borderlessButton)
            .fixedSize()
            ToolbarSeparator()
            GhostIconButton(
                systemImage: "rectangle.split.2x1",
                help: "Explorador — navegar por la carpeta de organización (⌘E)"
            ) {
                openWindow(id: "explorer")
            }
            GhostIconButton(systemImage: "text.alignleft", help: "Registro en vivo (⌘L)") {
                showLogViewer = true
            }
            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 24, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .controlSize(.small)
            .help("Ajustes (⌘A)")
        }
        .padding(.horizontal, J4I.Space.m)
        .padding(.vertical, 7)
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
