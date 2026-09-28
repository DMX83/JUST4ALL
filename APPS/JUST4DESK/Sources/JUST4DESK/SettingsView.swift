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
        .frame(width: 620, height: 460)
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

// MARK: - Piezas de Ajustes (F15.0)

/// Tarjeta de ajustes: cabecera de sección + tarjeta elevada con filas.
struct SettingsCard<Content: View>: View {
    let title: String
    var systemImage: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionHeader(title, systemImage: systemImage)
            J4ICard {
                VStack(alignment: .leading, spacing: 8) {
                    content
                }
            }
        }
    }
}

/// Fila de ajuste: etiqueta (con subtítulo opcional) y contenido a la derecha.
struct SettingsRow<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: J4I.Space.m) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12.5))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: J4I.Space.m)
            content
        }
    }
}

/// Nota pequeña dentro de una tarjeta de ajustes.
struct SettingsNote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Organización

private struct OrganizationSettingsView: View {
    @State private var rootPath: String = FilingConfiguration.rootPath ?? ""
    @State private var sourcePaths: [String] = FilingConfiguration.sourcePaths
    @State private var simulation = FilingConfiguration.simulationMode
    @State private var paused = FilingConfiguration.organizationPaused
    /// N5 — avisos del sistema al archivar (misma clave que usa `FilingNotifier`).
    @AppStorage(FilingNotifier.defaultsKey) private var notifyFiled = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: J4I.Space.l) {
                SettingsCard(title: "Carpeta de organización", systemImage: "folder") {
                    HStack(spacing: J4I.Space.s) {
                        Text(rootPath.isEmpty ? "Sin configurar" : (rootPath as NSString).abbreviatingWithTildeInPath)
                            .font(.system(size: 12))
                            .foregroundStyle(rootPath.isEmpty ? Color.secondary : Color.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: J4I.Space.s)
                        Button("Cambiar…") {
                            chooseFolder { path in
                                NotificationCenter.default.post(name: .j4iSetFilingRoot, object: path)
                            }
                        }
                        .controlSize(.small)
                    }
                }
                SettingsCard(title: "Carpetas de entrada", systemImage: "tray.and.arrow.down") {
                    if sourcePaths.isEmpty {
                        Text("Sin configurar")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(sourcePaths, id: \.self) { path in
                            HStack(spacing: 8) {
                                Image(systemName: "folder")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                Text((path as NSString).abbreviatingWithTildeInPath)
                                    .font(.system(size: 12))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer(minLength: J4I.Space.s)
                                Button("Quitar") {
                                    NotificationCenter.default.post(name: .j4iRemoveSourceFolder, object: path)
                                }
                                .controlSize(.small)
                            }
                            .padding(.vertical, 1)
                        }
                    }
                    HStack(spacing: J4I.Space.s) {
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
                    .controlSize(.small)
                    .padding(.top, 2)
                }
                SettingsCard(title: "Comportamiento", systemImage: "gearshape.2") {
                    Toggle("Modo simulación (no mover nada)", isOn: $simulation)
                        .onChange(of: simulation) { _, newValue in
                            NotificationCenter.default.post(name: .j4iSetSimulationMode, object: newValue)
                        }
                    Toggle("Organización pausada", isOn: $paused)
                        .onChange(of: paused) { _, newValue in
                            NotificationCenter.default.post(name: .j4iSetPaused, object: newValue)
                        }
                    Divider()
                    Toggle("Avisar al archivar (notificación del sistema)", isOn: $notifyFiled)
                    SettingsNote("Los avisos requieren la app instalada con su identificador (el DMG); en ejecución de desarrollo no se muestran. Apagado, la organización sigue funcionando igual.")
                    SettingsNote("Los cambios se aplican al momento en la ventana principal (y quedan guardados).")
                }
            }
            .padding(J4I.Space.l)
        }
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
        ScrollView {
            VStack(alignment: .leading, spacing: J4I.Space.l) {
                SettingsCard(title: "Clasificación con IA (DeepSeek)", systemImage: "sparkles") {
                    if hasKey {
                        Toggle("Usar la IA al clasificar", isOn: $enabled)
                            .onChange(of: enabled) { _, newValue in
                                // Fuente de verdad al momento: evita que refresh() reverte el toggle
                                // por la carrera con el puente de notificaciones.
                                AIControlCenter.shared.isEnabled = newValue
                                NotificationCenter.default.post(name: .j4iSetAIEnabled, object: newValue)
                                refresh()
                            }
                        Divider()
                        SettingsRow(title: "Límite diario de llamadas") {
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
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 4) {
                                    Button {
                                        commitDailyLimit(dailyLimit - 50)
                                    } label: {
                                        Image(systemName: "minus")
                                            .font(.system(size: 10, weight: .semibold))
                                            .frame(width: 18, height: 16)
                                    }
                                    .help("Bajar 50")
                                    Button {
                                        commitDailyLimit(dailyLimit + 50)
                                    } label: {
                                        Image(systemName: "plus")
                                            .font(.system(size: 10, weight: .semibold))
                                            .frame(width: 18, height: 16)
                                    }
                                    .help("Subir 50")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        Divider()
                        SettingsRow(title: "Uso") {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Hoy: \(usage.callsToday)/\(usage.dailyLimit) llamadas · \(usage.tokensToday.formatted()) tokens")
                                Text("Total: \(usage.callsTotal) llamadas · \(usage.tokensTotal.formatted()) tokens")
                            }
                            .font(.system(size: 11.5))
                            .monospacedDigit()
                            .foregroundStyle(usage.limitReached ? J4I.warning : Color.secondary)
                        }
                    } else {
                        Text("Sin clave de DeepSeek. Añade `DEEPSEEK_API_KEY=…` en el `.env.secrets` del repo (o en el entorno) y reinicia la app. Mientras, la clasificación usa solo reglas locales.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                SettingsCard(title: "Skill del clasificador", systemImage: "wand.and.stars") {
                    SettingsRow(title: "Versión") {
                        Text("v\(FilingSkill.version) · \(FilingSkill.curatedCases.count) casos curados")
                            .font(.system(size: 12, weight: .medium))
                    }
                    SettingsNote("La skill es interna y se afina con la app (sin edición manual); cada caso nuevo entra como prueba de regresión.")
                }
                SettingsCard(title: "Conocimiento local (aprendido)", systemImage: "brain") {
                    SettingsRow(title: "Reglas promovidas") {
                        Text("\(knowledgeStats.promotedCount) · características observadas: \(knowledgeStats.learnedEntries)")
                            .font(.system(size: 12, weight: .medium))
                            .monospacedDigit()
                    }
                    SettingsRow(title: "Clasificaciones sin IA") {
                        Text("Hoy: \(knowledgeStats.appliedToday) · Total: \(knowledgeStats.appliedTotal)")
                            .font(.system(size: 12, weight: .medium))
                            .monospacedDigit()
                    }
                    SettingsNote("Cada decisión de la IA y cada corrección tuya se resumen por característica (extensión de fichero y palabras del nombre de carpeta); con ≥3 coincidencias se promueve a regla local y las próximas unidades así se clasifican sin gastar tokens.")
                }
            }
            .padding(J4I.Space.l)
        }
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
                J4IEmptyState(
                    systemImage: "folder.badge.plus",
                    title: "Sin carpetas indexadas",
                    message: "Añade una carpeta para la búsqueda instantánea."
                ) {
                    Button("Añadir carpeta…") {
                        NotificationCenter.default.post(name: .j4iRequestAddRoot, object: nil)
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                List(roots) { root in
                    HStack(spacing: 10) {
                        Image(systemName: "folder")
                            .font(.system(size: 12))
                            .foregroundStyle(J4I.brand)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(root.displayName)
                                .font(.system(size: 12.5, weight: .medium))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text("\(root.entryCount) entradas · \(root.state)")
                                .font(.system(size: 11))
                                .monospacedDigit()
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
                BackfillStatusCard()
                    .padding(.horizontal, J4I.Space.m)
                    .padding(.top, J4I.Space.s)
            }
            Divider()
            HStack(spacing: J4I.Space.s) {
                Button("Añadir carpeta…") {
                    NotificationCenter.default.post(name: .j4iRequestAddRoot, object: nil)
                }
                Spacer()
                Button("Actualizar") { Task { await reload() } }
            }
            .controlSize(.small)
            .padding(J4I.Space.m)
        }
        .task {
            while !Task.isCancelled {
                await reload()
                await BackfillStatusModel.shared.refreshCounts()
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

// MARK: - Estado de los rellenos (auditoría 28-sep, deuda #3)

private struct BackfillStatusCard: View {
    @ObservedObject private var status = BackfillStatusModel.shared

    var body: some View {
        SettingsCard(title: "Rellenos del índice", systemImage: "arrow.triangle.2.circlepath") {
            SettingsRow(
                title: "Contenido",
                subtitle: "Textos extraídos de documentos (PDF/OCR, docx, xlsx…)"
            ) {
                Text("\(status.counts.contentWithText) con texto · \(status.counts.contentAttemptedEmpty) sin texto · \(status.counts.contentPending) pendientes")
                    .font(.system(size: 11.5))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            SettingsRow(
                title: "Vectores",
                subtitle: "Semántica local por documento (sin salir del Mac)"
            ) {
                Text("\(status.counts.embedded) de \(status.counts.files) ficheros · \(status.counts.embeddedContent) con contenido")
                    .font(.system(size: 11.5))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if let at = status.lastRunAt {
                Text("Última pasada (esta sesión, \(at.formatted(date: .omitted, time: .shortened))): \(status.lastExtracted) extraídos · \(status.lastEmpty) sin texto · \(status.lastMissing) ausentes")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
            HStack(spacing: J4I.Space.s) {
                if status.isRunning {
                    ProgressView()
                        .controlSize(.small)
                    Text(status.isContentRunning ? "Rellenando contenido…" : "Vectorizando documentos…")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Rellenar ahora") {
                    NotificationCenter.default.post(name: .j4iRequestBackfillNow, object: nil)
                }
                .controlSize(.small)
                .disabled(status.isRunning)
                .help("Re-extrae textos pendientes y vectoriza documentos sin esperar al próximo arranque")
            }
        }
    }
}

// MARK: - Acerca de

private struct AboutSettingsView: View {
    @State private var hasAIKey = false
    @AppStorage("j4i.listDensity") private var listDensity: J4I.ListDensity = .comfortable

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: J4I.Space.l) {
                SettingsCard(title: "JUST4DESK", systemImage: "info.circle") {
                    HStack(spacing: J4I.Space.m) {
                        BrandMark(size: 42)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("JUST4DESK")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                            Text(BuildInfo.displayLabel)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.bottom, 2)
                    Divider()
                    SettingsRow(title: "Clasificación IA") {
                        Text(hasAIKey ? "Activada (DeepSeek)" : "Solo reglas locales (sin clave)")
                            .font(.system(size: 12, weight: .medium))
                    }
                    SettingsRow(title: "Carpeta de organización") {
                        Text(FilingConfiguration.rootPath ?? "Sin configurar")
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                SettingsCard(title: "Apariencia", systemImage: "rectangle.compress.vertical") {
                    SettingsRow(
                        title: "Densidad de las listas",
                        subtitle: "Resultados de búsqueda, explorador y «Por revisar»"
                    ) {
                        Picker("", selection: $listDensity) {
                            ForEach(J4I.ListDensity.allCases) { option in
                                Text(option.label).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                }
                SettingsCard(title: "Atajos", systemImage: "keyboard") {
                    HStack(spacing: J4I.Space.l) {
                        KeycapBadge(keys: "⌘E", label: "Explorador")
                        KeycapBadge(keys: "⌘R", label: "Por revisar")
                        KeycapBadge(keys: "⌘L", label: "Registro")
                        KeycapBadge(keys: "⌘A", label: "Ajustes")
                        Spacer()
                    }
                }
                SettingsCard(title: "Diagnóstico", systemImage: "wrench.and.screwdriver") {
                    HStack(spacing: J4I.Space.s) {
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
                    .controlSize(.small)
                }
                SettingsCard(title: "Créditos", systemImage: "person.2") {
                    Text("Hecho por dmx83 · Motores compartidos J4SHARED (índice J4IIndex, núcleo J4ICore)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("Servidor MCP incluido para agentes (docs/MCP.md) · Icono provisional generado (28-sep)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(J4I.Space.l)
        }
        .onAppear {
            hasAIKey = DeepSeekKeyResolver.resolve() != nil
        }
    }
}
