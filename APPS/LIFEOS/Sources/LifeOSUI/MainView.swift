import LifeOSAPI
import SwiftUI

/// Ventana principal: barra lateral translúcida del sistema y, al lado, la
/// sección elegida.
public struct MainView: View {
    public enum Pane: String, CaseIterable, Identifiable, Hashable {
        case today
        case capture
        case journal
        case agenda
        case tasks
        case insights
        case inbox
        case settings

        public var id: String { rawValue }

        /// El orden de las secciones **es** el orden de la barra lateral y de los atajos
        /// ⌘1…⌘8: se lee de arriba abajo sin saltos. El dueño pidió el 30-sep-2026 que el
        /// **Diario** fuera antes que la **Agenda** (es lo primero que se escribe del día),
        /// y al moverlo se renumeran los atajos para que no quede un 1, 2, 5, 3, 4.
        var title: String {
            switch self {
            case .today: return "Hoy"
            case .capture: return "Capturar"
            case .journal: return "Diario"
            case .agenda: return "Agenda"
            case .tasks: return "Ejecutar"
            case .insights: return "Buscar"
            case .inbox: return "Bandeja"
            case .settings: return "Ajustes"
            }
        }

        var systemImage: String {
            switch self {
            case .today: return "sun.horizon.fill"
            case .capture: return "square.and.pencil"
            case .journal: return "book.closed.fill"
            case .agenda: return "calendar"
            case .tasks: return "checklist"
            case .insights: return "magnifyingglass"
            case .inbox: return "tray.full.fill"
            case .settings: return "gearshape.fill"
            }
        }

        var shortcut: KeyEquivalent {
            switch self {
            case .today: return "1"
            case .capture: return "2"
            case .journal: return "3"
            case .agenda: return "4"
            case .tasks: return "5"
            case .insights: return "6"
            case .inbox: return "7"
            case .settings: return "8"
            }
        }
    }

    @ObservedObject private var model: LifeOSModel
    @State private var pane: Pane?
    /// Si hay algo arrastrándose encima: se enseña a dónde va a ir a parar.
    @State private var isDropTarget = false

    public init(model: LifeOSModel) {
        self.model = model
        let stored = model.storedPane
        _pane = State(initialValue: Pane(rawValue: stored) ?? .today)
    }

    public var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 214, max: 260)
        } detail: {
            detail
                .frame(minWidth: 560, minHeight: 460)
                .background(LifeOSTheme.canvas)
        }
        .safeAreaInset(edge: .top, spacing: 0) { intakeBanner }
        .overlay { dropTarget }
        .onChange(of: pane) { _, newValue in
            guard let newValue else { return }
            model.rememberPane(newValue.rawValue)
        }
        .background(LifeOSTheme.canvas)
        // Arrastrar a la ventana es la forma más natural de mandar algo a LifeOS.
        // Un fichero va como documento; un enlace o un texto suelto, como
        // anotación. Se aceptan los dos sin que el usuario tenga que elegir.
        .dropDestination(for: URL.self) { urls, _ in
            handleDrop(urls)
        } isTargeted: { isDropTarget = $0 }
        .dropDestination(for: String.self) { texts, _ in
            let joined = texts.joined(separator: "\n")
            guard !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            Task { await model.receive(.text(joined)) }
            return true
        } isTargeted: { isDropTarget = $0 }
    }

    private func handleDrop(_ urls: [URL]) -> Bool {
        let files = urls.filter(\.isFileURL)
        let links = urls.filter { !$0.isFileURL }
        guard !files.isEmpty || !links.isEmpty else { return false }
        Task {
            if !files.isEmpty { await model.receive(files: files) }
            if !links.isEmpty {
                await model.receive(.text(links.map(\.absoluteString).joined(separator: "\n")))
            }
        }
        return true
    }

    @ViewBuilder
    private var dropTarget: some View {
        if isDropTarget {
            RoundedRectangle(cornerRadius: LifeOSRadius.panel, style: .continuous)
                .strokeBorder(LifeOSTheme.brand, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                .background(
                    RoundedRectangle(cornerRadius: LifeOSRadius.panel, style: .continuous)
                        .fill(LifeOSTheme.brand.opacity(0.07))
                )
                .overlay(alignment: .center) {
                    VStack(spacing: LifeOSSpace.xs) {
                        Image(systemName: "tray.and.arrow.down.fill")
                            .font(.system(size: 22, weight: .semibold))
                        Text("Suelta para guardarlo en LifeOS")
                            .font(LifeOSFont.label)
                    }
                    .foregroundStyle(LifeOSTheme.brand)
                    .padding(LifeOSSpace.m)
                    .background(
                        RoundedRectangle(cornerRadius: LifeOSRadius.md, style: .continuous)
                            .fill(LifeOSTheme.surface)
                    )
                }
                .padding(LifeOSSpace.m)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    /// Lo que pasó con lo último que llegó de fuera (Servicios, arrastrar, abrir).
    @ViewBuilder
    private var intakeBanner: some View {
        if let message = model.intakeMessage {
            HStack(alignment: .top, spacing: LifeOSSpace.s) {
                Image(systemName: model.intakeIsProblem ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(model.intakeIsProblem ? LifeOSTheme.warning : LifeOSTheme.positive)
                VStack(alignment: .leading, spacing: LifeOSSpace.xs) {
                    Text(message)
                        .font(LifeOSFont.bodySmall)
                        .foregroundStyle(LifeOSTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let offer = model.intakeNoteOffer {
                        Button(offer.label) {
                            Task { await model.acceptIntakeNote() }
                        }
                        .buttonStyle(LifeOSGhostButtonStyle())
                    }
                }
                Spacer(minLength: 0)
                if model.intakeBusy {
                    ProgressView().controlSize(.small)
                }
                Button {
                    model.dismissIntakeMessage()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(LifeOSGhostButtonStyle())
                .labelStyle(.iconOnly)
            }
            .padding(.horizontal, LifeOSSpace.l)
            .padding(.vertical, LifeOSSpace.s)
            .background(LifeOSTheme.surface)
            .overlay(alignment: .bottom) { LifeOSDivider() }
        }
    }

    // MARK: - Barra lateral

    private var sidebar: some View {
        List(selection: $pane) {
            ForEach(Pane.allCases) { item in
                Label(item.title, systemImage: item.systemImage)
                    .badge(badge(for: item))
                    .tag(item)
                    .keyboardShortcut(item.shortcut, modifiers: .command)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) { sidebarHeader }
        .safeAreaInset(edge: .bottom, spacing: 0) { sidebarFooter }
    }

    /// Contadores de la barra lateral: sólo aparecen si hay algo que atender.
    private func badge(for item: Pane) -> Int {
        switch item {
        case .inbox:
            return model.inbox.count
        case .tasks:
            return model.tasks.filter(\.isOpen).count
        case .agenda:
            return model.agendaDuplicates.count
        default:
            return 0
        }
    }

    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: LifeOSSpace.m) {
            HStack(spacing: LifeOSSpace.s) {
                BrandMark(size: 26)
                VStack(alignment: .leading, spacing: 0) {
                    Text("LifeOS")
                        .font(LifeOSFont.subtitle)
                        .foregroundStyle(LifeOSTheme.textPrimary)
                    Text(model.user?.displayName ?? "Sin sesión")
                        .font(LifeOSFont.caption)
                        .foregroundStyle(LifeOSTheme.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            LifeOSDivider()
        }
        .padding(.horizontal, LifeOSSpace.m)
        .padding(.top, LifeOSSpace.m)
        .padding(.bottom, LifeOSSpace.s)
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: LifeOSSpace.s) {
            LifeOSDivider()
            if !model.queued.isEmpty {
                Button {
                    Task { await model.flushOutbox() }
                } label: {
                    HStack(spacing: LifeOSSpace.xs) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 10, weight: .bold))
                        Text("\(model.queued.count) sin enviar")
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(LifeOSTheme.warning)
                }
                .buttonStyle(LifeOSGhostButtonStyle())
            }
            HStack(spacing: LifeOSSpace.xs) {
                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("Actualizar", systemImage: "arrow.clockwise")
                }
                .buttonStyle(LifeOSGhostButtonStyle())
                .disabled(model.busy)

                Spacer(minLength: 0)

                Button {
                    Task { await model.signOut() }
                } label: {
                    Label("Salir", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .buttonStyle(LifeOSGhostButtonStyle())
                .help("Cerrar sesión")
            }
            .labelStyle(.iconOnly)
        }
        .padding(.horizontal, LifeOSSpace.m)
        .padding(.bottom, LifeOSSpace.s)
    }

    // MARK: - Detalle

    @ViewBuilder
    private var detail: some View {
        switch pane ?? .today {
        case .today:
            TodayView(model: model) { target in pane = target }
        case .capture:
            CaptureView(model: model, focusOnAppear: true)
        case .agenda:
            AgendaView(model: model)
        case .tasks:
            TasksView(model: model)
        case .journal:
            JournalView(model: model)
        case .insights:
            InsightsView(model: model)
        case .inbox:
            InboxView(model: model)
        case .settings:
            SettingsView(model: model)
        }
    }
}

/// Raíz: decide entre «comprobando», la puerta de entrada y la app.
public struct RootView: View {
    @ObservedObject private var model: LifeOSModel
    @State private var showsEscape = false

    public init(model: LifeOSModel) {
        self.model = model
    }

    public var body: some View {
        Group {
            switch model.phase {
            case .restoring:
                restoring
            case .signedOut:
                LoginView(model: model)
            case .signedIn:
                MainView(model: model)
            }
        }
        .tint(LifeOSTheme.brand)
        .onChange(of: model.phase) { _, phase in
            if case .restoring = phase { return }
            showsEscape = false
        }
    }

    private var restoring: some View {
        VStack(spacing: LifeOSSpace.m) {
            BrandMark(size: 52)
            ProgressView()
                .controlSize(.small)
                .padding(.top, LifeOSSpace.s)
            Text("Comprobando la sesión…")
                .font(LifeOSFont.bodySmall)
                .foregroundStyle(LifeOSTheme.textSecondary)

            // Si el llavero o el servidor tardan, se puede seguir: nunca hay una
            // pantalla girando sin salida.
            if showsEscape {
                VStack(spacing: LifeOSSpace.s) {
                    Text("Si tarda, es posible que macOS esté pidiendo permiso para el llavero o que el servidor no responda.")
                        .font(LifeOSFont.caption)
                        .foregroundStyle(LifeOSTheme.textTertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 340)
                    Button("Escribir mis datos") {
                        model.continueWithoutSession()
                    }
                    .buttonStyle(LifeOSPrimaryButtonStyle())
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LifeOSTheme.canvas)
        .task {
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation(LifeOSMotion.standard) { showsEscape = true }
        }
    }
}
