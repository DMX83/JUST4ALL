import AppKit
import Carbon.HIToolbox
import LifeOSUI
import SwiftUI

// MARK: - Panel flotante de captura

/// Panel sin marco que puede ser «key»: imprescindible para poder escribir en él
/// sin activar antes una ventana de la app.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Panel flotante de captura rápida, centrado arriba de la pantalla.
///
/// Mismo patrón que el buscador rápido de JUST4DESK (G4): `NSPanel` borderless
/// con material, se cierra con Esc o al perder el foco.
@MainActor
final class QuickCapturePanelController: NSObject, NSWindowDelegate {
    private var panel: KeyablePanel?
    private weak var model: LifeOSModel?

    func attach(model: LifeOSModel) {
        self.model = model
    }

    func toggle() {
        if let panel, panel.isVisible {
            close()
        } else {
            show()
        }
    }

    func close() {
        panel?.orderOut(nil)
    }

    /// Abre el panel. Lo usa también «enviar a LifeOS»: cuando llega texto de
    /// fuera, la propuesta tiene que verse para poder revisarla.
    func show() {
        guard let model else { return }
        let panel = self.panel ?? makePanel(model: model)
        self.panel = panel
        position(panel)
        if !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
        }
        panel.makeKeyAndOrderFront(nil)
    }

    private func makePanel(model: LifeOSModel) -> KeyablePanel {
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 240),
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
            rootView: QuickCaptureView(
                model: model,
                onClose: { [weak self] in self?.close() }
            )
        )
        return panel
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(
            NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 150)
        )
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }
}

// MARK: - Atajo global (Carbon)

/// Atajo global vía `RegisterEventHotKey`: se consume la combinación en todo el
/// sistema sin pedir permiso de Accesibilidad. Devuelve `nil` si el registro
/// falla (por ejemplo, si otra app ya usa ⌥Espacio).
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
                Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue().action()
                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &handlerRef
        )
        guard installStatus == noErr else { return nil }

        // 'J4LS' — identificador propio para no chocar con otros atajos de la suite.
        let hotKeyID = EventHotKeyID(signature: OSType(0x4A34_4C53), id: 1)
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard registerStatus == noErr else {
            if let handlerRef { RemoveEventHandler(handlerRef) }
            self.handlerRef = nil
            return nil
        }
    }

    /// Suelta el atajo. Hace falta para poder **apagarlo desde Ajustes** sin
    /// reiniciar: si no se libera, la combinación sigue secuestrada.
    func release() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
    }

    deinit {
        release()
    }
}
