import AppKit
import SwiftUI
import J4IAI
import J4ICore
import J4IFiling
import J4IIndex

/// Ventana de Ajustes (⌘,) con las configuraciones de la app.
struct SettingsView: View {
    private enum Tab: String {
        case organization
        case ai
        case index
        case about
    }

    @State private var selection: Tab = .organization

    var body: some View {
        TabView(selection: $selection) {
            OrganizationSettingsView()
                .tabItem { Label("Organización", systemImage: "folder") }
                .tag(Tab.organization)
            AISettingsView()
                .tabItem { Label("IA", systemImage: "sparkles") }
                .tag(Tab.ai)
            IndexSettingsView()
                .tabItem { Label("Indexado", systemImage: "magnifyingglass") }
                .tag(Tab.index)
            AboutSettingsView()
                .tabItem { Label("Acerca de", systemImage: "info.circle") }
                .tag(Tab.about)
        }
        .frame(width: 560, height: 400)
        .onAppear(perform: applyPendingTab)
        .onReceive(NotificationCenter.default.publisher(for: .j4iOpenAISettings)) { _ in
            applyPendingTab()
        }
    }

    /// Recoge la pestaña pedida por el atajo ⌘I (y la limpia).
    private func applyPendingTab() {
        switch SettingsTabRouter.pendingTab {
        case "ai": selection = .ai
        case "organization": selection = .organization
        case "index": selection = .index
        case "about": selection = .about
        default: break
        }
        SettingsTabRouter.pendingTab = nil
    }
}

// MARK: - Organización

private struct OrganizationSettingsView: View {
    @State private var rootPath: String = FilingConfiguration.rootPath ?? ""
    @State private var sourcePaths: [String] = FilingConfiguration.sourcePaths
    @State private var simulation = FilingConfiguration.simulationMode
    @State private var paused = FilingConfiguration.organizationPaused

    var body: some View {
        Form {
            Section("Carpetas") {
                LabeledContent("Carpeta de organización") {
                    HStack(spacing: 8) {
                        Text(rootPath.isEmpty ? "Sin configurar" : (rootPath as NSString).abbreviatingWithTildeInPath)
                            .foregroundStyle(rootPath.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Cambiar…") {
                            chooseFolder { path in
                                NotificationCenter.default.post(name: .j4iSetFilingRoot, object: path)
                            }
                        }
                    }
                }
                LabeledContent("Carpetas de entrada") {
                    VStack(alignment: .trailing, spacing: 4) {
                        ForEach(sourcePaths, id: \.self) { path in
                            HStack(spacing: 8) {
                                Text((path as NSString).abbreviatingWithTildeInPath)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Button("Quitar") {
                                    NotificationCenter.default.post(name: .j4iRemoveSourceFolder, object: path)
                                }
                                .controlSize(.small)
                            }
                        }
                        if sourcePaths.isEmpty {
                            Text("Sin configurar")
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 8) {
                            Button("Añadir…") {
                                chooseFolder { path in
                                    NotificationCenter.default.post(name: .j4iAddSourceFolder, object: path)
                                }
                            }
                            Button("Usar ~/Descargas") {
                                NotificationCenter.default.post(name: .j4iAddSourceFolder, object: FilingConfiguration.suggestedSourcePath)
                            }
                            Button("Usar ~/Downloads") {
                                NotificationCenter.default.post(name: .j4iAddSourceFolder, object: FilingConfiguration.suggestedDownloadsPath)
                            }
                        }
                    }
                }
            }
            Section("Comportamiento") {
                Toggle("Modo simulación (no mover nada)", isOn: $simulation)
                    .onChange(of: simulation) { _, newValue in
                        NotificationCenter.default.post(name: .j4iSetSimulationMode, object: newValue)
                    }
                Toggle("Organización pausada", isOn: $paused)
                    .onChange(of: paused) { _, newValue in
                        NotificationCenter.default.post(name: .j4iSetPaused, object: newValue)
                    }
            }
            Text("Los cambios se aplican al momento en la ventana principal (y quedan guardados).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .j4iFilingConfigChanged)) { _ in
            reload()
        }
    }

    private func reload() {
        rootPath = FilingConfiguration.rootPath ?? ""
        sourcePaths = FilingConfiguration.sourcePaths
        simulation = FilingConfiguration.simulationMode
        paused = FilingConfiguration.organizationPaused
    }

    private func chooseFolder(_ apply: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Elegir"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        apply(url.path)
    }
}

// MARK: - IA

private struct AISettingsView: View {
    @State private var enabled = AIControlCenter.shared.usage().isEnabled
    @State private var dailyLimit = AIControlCenter.shared.usage().dailyLimit
    @State private var dailyLimitText = "\(AIControlCenter.shared.usage().dailyLimit)"
    @FocusState private var capFieldFocused: Bool
    @State private var usage = AIControlCenter.shared.usage()
    @State private var knowledgeStats = LocalKnowledgeStore.shared.stats()
    @State private var hasKey = DeepSeekKeyResolver.resolve() != nil

    var body: some View {
        Form {
            Section("Clasificación con IA (DeepSeek)") {
                if hasKey {
                    Toggle("Usar la IA al clasificar", isOn: $enabled)
                        .onChange(of: enabled) { _, newValue in
                            // Fuente de verdad al momento: evita que refresh() reverte el toggle
                            // por la carrera con el puente de notificaciones.
                            AIControlCenter.shared.isEnabled = newValue
                            NotificationCenter.default.post(name: .j4iSetAIEnabled, object: newValue)
                            refresh()
                        }
                    LabeledContent("Límite diario de llamadas") {
                        HStack(spacing: 8) {
                            TextField("", text: $dailyLimitText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 72)
                                .multilineTextAlignment(.trailing)
                                .focused($capFieldFocused)
                                .onChange(of: dailyLimitText) { _, newValue in
                                    // Solo dígitos (máx. 4): las letras no llegan a entrar.
                                    let digits = String(newValue.filter(\.isNumber).prefix(4))
                                    if digits != newValue {
                                        dailyLimitText = digits
                                    }
                                }
                                .onSubmit { commitDailyLimitText() }
                                .onChange(of: capFieldFocused) { _, focused in
                                    if !focused { commitDailyLimitText() }
                                }
                                .help("Escribe el número y pulsa Enter (o usa los botones ± 50)")
                            Text("llamada(s)")
                                .foregroundStyle(.secondary)
                            Stepper("", value: $dailyLimit, in: 0...5000, step: 50)
                                .labelsHidden()
                                .onChange(of: dailyLimit) { _, newValue in
                                    commitDailyLimit(newValue)
                                }
                        }
                    }
                    LabeledContent("Uso") {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Hoy: \(usage.callsToday)/\(usage.dailyLimit) llamadas · \(usage.tokensToday.formatted()) tokens")
                            Text("Total: \(usage.callsTotal) llamadas · \(usage.tokensTotal.formatted()) tokens")
                        }
                        .foregroundStyle(usage.limitReached ? Color.orange : Color.secondary)
                    }
                } else {
                    Text("Sin clave de DeepSeek. Añade `DEEPSEEK_API_KEY=…` en el `.env.secrets` del repo (o en el entorno) y reinicia la app. Mientras, la clasificación usa solo reglas locales.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Skill del clasificador") {
                LabeledContent("Versión") {
                    Text("v\(FilingSkill.version) · \(FilingSkill.curatedCases.count) casos curados")
                }
                Text("La skill es interna y se afina con la app (sin edición manual); cada caso nuevo entra como prueba de regresión.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Conocimiento local (aprendido)") {
                LabeledContent("Reglas promovidas") {
                    Text("\(knowledgeStats.promotedCount) · características observadas: \(knowledgeStats.learnedEntries)")
                }
                LabeledContent("Clasificaciones sin IA") {
                    Text("Hoy: \(knowledgeStats.appliedToday) · Total: \(knowledgeStats.appliedTotal)")
                }
                Text("Cada decisión de la IA y cada corrección tuya se resumen por característica (extensión de fichero y palabras del nombre de carpeta); con ≥3 coincidencias se promueve a regla local y las próximas unidades así se clasifican sin gastar tokens.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: .j4iFilingConfigChanged)) { _ in
            refresh()
        }
    }

    private func refresh() {
        usage = AIControlCenter.shared.usage()
        enabled = usage.isEnabled
        dailyLimit = usage.dailyLimit
        if !capFieldFocused {
            dailyLimitText = "\(usage.dailyLimit)"
        }
        knowledgeStats = LocalKnowledgeStore.shared.stats()
        hasKey = DeepSeekKeyResolver.resolve() != nil
    }

    /// Aplica un cap nuevo **al momento** (sin esperar al puente de notificaciones): actualiza la
    /// fuente de verdad, avisa al pipeline y sincroniza ambos campos. Guard anti-doble-post para
    /// el caso de reentrada (el stepper dispara el mismo camino).
    private func commitDailyLimit(_ value: Int) {
        let clamped = min(max(value, 0), 5000)
        dailyLimit = clamped
        dailyLimitText = "\(clamped)"
        guard AIControlCenter.shared.dailyLimit != clamped else { return }
        AIControlCenter.shared.dailyLimit = clamped
        NotificationCenter.default.post(name: .j4iSetAIDailyLimit, object: clamped)
        usage = AIControlCenter.shared.usage()
    }

    /// Interpreta el texto del campo (solo dígitos) y lo aplica; si está vacío, deja el valor actual.
    private func commitDailyLimitText() {
        let parsed = Int(dailyLimitText.filter(\.isNumber)) ?? dailyLimit
        commitDailyLimit(parsed)
    }
}

// MARK: - Indexado

private struct IndexSettingsView: View {
    struct RootInfo: Identifiable {
        let id: Int64
        let displayName: String
        let state: String
        let entryCount: Int64
    }

    @State private var roots: [RootInfo] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if roots.isEmpty {
                ContentUnavailableView {
                    Label("Sin carpetas indexadas", systemImage: "folder.badge.plus")
                } description: {
                    Text("Añade una carpeta para la búsqueda instantánea.")
                } actions: {
                    Button("Añadir carpeta…") {
                        NotificationCenter.default.post(name: .j4iRequestAddRoot, object: nil)
                    }
                }
            } else {
                List(roots) { root in
                    HStack(spacing: 10) {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(root.displayName)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text("\(root.entryCount) entradas · \(root.state)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Reindexar") {
                            NotificationCenter.default.post(name: .j4iRequestRootReindex, object: root.id)
                        }
                        Button("Quitar", role: .destructive) {
                            NotificationCenter.default.post(name: .j4iRequestRootRemoval, object: root.id)
                        }
                    }
                    .controlSize(.small)
                }
                .listStyle(.inset)
            }
            Divider()
            HStack {
                Button("Añadir carpeta…") {
                    NotificationCenter.default.post(name: .j4iRequestAddRoot, object: nil)
                }
                Spacer()
                Button("Actualizar") { Task { await reload() } }
            }
            .controlSize(.small)
            .padding(10)
        }
        .task {
            while !Task.isCancelled {
                await reload()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func reload() async {
        let all = (try? await SearchIndex.shared.allRoots()) ?? []
        var infos: [RootInfo] = []
        for root in all {
            let status = try? await SearchIndex.shared.rootStatus(id: root.id)
            infos.append(
                RootInfo(
                    id: root.id,
                    displayName: (root.path as NSString).abbreviatingWithTildeInPath,
                    state: stateLabel(status?.state ?? .pending),
                    entryCount: status?.entryCount ?? 0
                )
            )
        }
        roots = infos
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

// MARK: - Acerca de

private struct AboutSettingsView: View {
    @State private var hasAIKey = false

    var body: some View {
        Form {
            Section("JUST4INDEX") {
                LabeledContent("Versión", value: BuildInfo.displayLabel)
                LabeledContent("Clasificación IA", value: hasAIKey ? "Activada (DeepSeek)" : "Solo reglas locales (sin clave)")
                LabeledContent("Carpeta de organización") {
                    Text((FilingConfiguration.rootPath ?? "Sin configurar") as NSString as String)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                LabeledContent("Atajos", value: "⌘E explorador · ⌘R revisar · ⌘L registro · ⌘A ajustes")
            }
            Section("Diagnóstico") {
                HStack(spacing: 8) {
                    Button("Abrir registro (⌘L)") {
                        NotificationCenter.default.post(name: .j4iShowLogViewer, object: nil)
                    }
                    Button("Revelar archivo de log") {
                        if let logURL = J4Log.fileURL {
                            NSWorkspace.shared.activateFileViewerSelecting([logURL])
                        }
                    }
                    Button("Abrir explorador (⌘E)") {
                        NotificationCenter.default.post(name: .j4iOpenExplorer, object: nil)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            hasAIKey = DeepSeekKeyResolver.resolve() != nil
        }
    }
}
