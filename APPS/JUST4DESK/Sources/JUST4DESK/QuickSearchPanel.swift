import AppKit
import Carbon.HIToolbox
import Combine
import J4ICore
import J4IIndex
import SwiftUI

// MARK: - Panel flotante (⌥Espacio)

/// G4 — Atajo global (⌥Espacio) + buscador flotante: presencia inmediata desde cualquier app.
///
/// El panel es un `NSPanel` sin marco con material, centrado arriba de la pantalla; se ajusta al
/// contenido (campo solo → tarjeta compacta; con resultados → crece). Esc o perder el foco cierra.
@MainActor
final class QuickSearchPanelController: NSObject, NSWindowDelegate {
    private var panel: KeyablePanel?
    private var cancellables = Set<AnyCancellable>()
    private let model = QuickSearchModel()

    func toggle() {
        if let panel, panel.isVisible {
            close()
        } else {
            show()
        }
    }

    func close() {
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        J4Log.debug(.app, "Buscador rápido: cerrado.")
    }

    private func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        model.reset()
        position(panel)
        if !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
        }
        panel.makeKeyAndOrderFront(nil)
        J4Log.debug(.app, "Buscador rápido: abierto (⌥Espacio).")
        resizeToFit()
    }

    private func makePanel() -> KeyablePanel {
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 64),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.contentView = NSHostingView(
            rootView: QuickSearchView(model: model, onClose: { [weak self] in self?.close() })
        )
        model.$hits
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.resizeToFit() }
            .store(in: &cancellables)
        model.$errorMessage
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.resizeToFit() }
            .store(in: &cancellables)
        return panel
    }

    /// Ajusta el alto del panel al contenido (el borde superior se queda fijo).
    private func resizeToFit() {
        guard let panel, let hosting = panel.contentView as? NSHostingView<QuickSearchView> else { return }
        DispatchQueue.main.async {
            let fitting = hosting.fittingSize
            guard fitting.height > 0, fitting.width > 0 else { return }
            var frame = panel.frame
            let top = frame.maxY
            frame.size = NSSize(width: max(fitting.width, 620), height: fitting.height)
            frame.origin.y = top - fitting.height
            panel.setFrame(frame, display: true, animate: panel.isVisible)
        }
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 140))
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }
}

/// Panel sin marco que puede ser key (imprescindible para escribir sin activar una ventana).
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Atajo global (Carbon)

/// Atajo global vía `RegisterEventHotKey`: consume la combinación en todo el sistema (no hace
/// falta permiso de Accesibilidad). Si el registro falla (conflicto), devuelve `nil`.
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let instance = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                instance.action()
                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &handlerRef
        )
        guard installStatus == noErr else { return nil }

        let hotKeyID = EventHotKeyID(signature: OSType(0x4A34_444B) /* 'J4DK' */, id: 1)
        let registerStatus = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard registerStatus == noErr else {
            if let handlerRef { RemoveEventHandler(handlerRef) }
            self.handlerRef = nil
            return nil
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}

// MARK: - Modelo y vista

/// Estado del buscador rápido: consulta con debounce contra el índice compartido.
@MainActor
final class QuickSearchModel: ObservableObject {
    @Published var query = "" {
        didSet { scheduleSearch() }
    }
    @Published private(set) var hits: [IndexSearchHit] = []
    @Published var errorMessage: String?

    private let index: SearchIndex
    private var searchTask: Task<Void, Never>?

    init(index: SearchIndex = .shared) {
        self.index = index
    }

    var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func reset() {
        searchTask?.cancel()
        query = ""
        hits = []
        errorMessage = nil
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard let self, !Task.isCancelled else { return }
            await self.performSearch()
        }
    }

    func performSearch() async {
        let term = trimmedQuery
        guard !term.isEmpty else {
            hits = []
            return
        }
        let request = IndexSearchRequest(query: term, filters: IndexSearchFilters(), limit: 8, includeContent: false)
        do {
            hits = try await index.search(request)
            errorMessage = nil
        } catch {
            hits = []
            errorMessage = error.localizedDescription
        }
    }

    /// Abre un resultado (devuelve `false` y deja aviso si el fichero ya no existe).
    @discardableResult
    func open(_ hit: IndexSearchHit) -> Bool {
        let url = URL(fileURLWithPath: hit.entry.path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = "El archivo ya no existe en esa ruta."
            J4Log.warn(.search, "Buscador rápido: «\(hit.entry.name)» ya no existe.")
            return false
        }
        NSWorkspace.shared.open(url)
        J4Log.debug(.search, "Buscador rápido: abierto «\(hit.entry.name)».")
        return true
    }

    /// Pasa a la ventana «Buscar» con la consulta actual (⌘↵).
    func openFullSearch() {
        let term = trimmedQuery
        NotificationCenter.default.post(name: .j4iOpenSearch, object: term.isEmpty ? nil : term)
        J4Log.debug(.search, "Buscador rápido: pasar a la ventana completa («\(term)»).")
    }
}

/// Tarjeta del buscador flotante (material, esquinas redondeadas, resultados compactos).
struct QuickSearchView: View {
    @ObservedObject var model: QuickSearchModel
    let onClose: () -> Void
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                BrandMark(size: 22)
                TextField("Buscar en tu archivo…", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($fieldFocused)
                    .onSubmit { submit() }
                    .onExitCommand { onClose() }
                if !model.trimmedQuery.isEmpty {
                    Text("↵ abrir · ⌘↵ ver todos")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .fixedSize()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            if let error = model.errorMessage {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(J4I.danger)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !model.hits.isEmpty {
                Divider().opacity(0.4)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(model.hits.prefix(6), id: \.entry.id) { hit in
                        Button {
                            if model.open(hit) { onClose() }
                        } label: {
                            hitRow(hit)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
                Divider().opacity(0.4)
                HStack(spacing: 8) {
                    Spacer()
                    Button("Ver todos los resultados") { openFull() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(J4I.brand)
                    Text("⌘↵")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            } else if !model.trimmedQuery.isEmpty {
                Text("Sin resultados en el índice.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 620)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12))
        )
        .onAppear { fieldFocused = true }
        .background(
            Button("Ver todos") { openFull() }
                .keyboardShortcut(.return, modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        )
    }

    private func hitRow(_ hit: IndexSearchHit) -> some View {
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
        .padding(.vertical, 5)
        .padding(.horizontal, 14)
        .contentShape(Rectangle())
        .hoverHighlight(cornerRadius: 6, intensity: 0.06)
    }

    private func submit() {
        if let first = model.hits.first {
            if model.open(first) { onClose() }
        } else if !model.trimmedQuery.isEmpty {
            openFull()
        }
    }

    private func openFull() {
        model.openFullSearch()
        NSApp.activate(ignoringOtherApps: true)
        onClose()
    }
}
