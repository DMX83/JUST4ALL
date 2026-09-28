import AppKit
import SwiftUI

/// Monitor de la barra espaciadora para QuickLook (compartido por explorador y buscador).
///
/// `NSEvent` no es `@MainActor`: este puente no aislado lo actualiza el view model (siempre en
/// el hilo principal) y el monitor solo lee. Evita capturar la tecla mientras se escribe en un
/// campo de texto (el campo de búsqueda usa el editor de campo: `NSTextView`).
final class QuickLookSpaceMonitor {
    var window: NSWindow?
    var urls: [URL] = []
    private var token: Any?

    func install() {
        guard token == nil else { return }
        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    func handle(_ event: NSEvent) -> NSEvent? {
        guard event.keyCode == 49, !event.isARepeat else { return event }
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty else { return event }
        let quickLook = QuickLookController.shared
        if quickLook.isVisible, event.window === quickLook.panelWindow {
            quickLook.close()
            return nil
        }
        guard event.window === window else { return event }
        guard !(window?.firstResponder is NSTextView) else { return event }
        guard !urls.isEmpty else { return event }
        quickLook.toggle(urls: urls)
        return nil
    }

    func uninstall() {
        if let token {
            NSEvent.removeMonitor(token)
            self.token = nil
        }
    }
}

/// Captura la `NSWindow` que aloja la vista (para el monitor de la barra espaciadora).
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onWindow(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onWindow(nsView.window) }
    }
}
