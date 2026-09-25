import AppKit
import Quartz

/// Vista previa rápida (barra espaciadora) del explorador mediante el panel compartido de QuickLook.
///
/// La app no es document-based: el control del panel se hace directamente (dataSource/delegate)
/// y, además, `J4IAppDelegate` implementa `acceptsPreviewPanelControl` como último eslabón de la
/// cadena de respondedores (Apple exige que alguien acepte el control del panel).
final class QuickLookController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookController()

    private(set) var previewURLs: [URL] = []

    var isVisible: Bool {
        QLPreviewPanel.sharedPreviewPanelExists() && (QLPreviewPanel.shared()?.isVisible ?? false)
    }

    var panelWindow: NSWindow? {
        QLPreviewPanel.sharedPreviewPanelExists() ? QLPreviewPanel.shared() : nil
    }

    func toggle(urls: [URL]) {
        guard !urls.isEmpty else { return }
        if isVisible {
            close()
        } else {
            show(urls: urls)
        }
    }

    func show(urls: [URL]) {
        guard !urls.isEmpty else { return }
        previewURLs = urls
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.delegate = self
        panel.currentPreviewItemIndex = 0
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    /// Actualiza los elementos del panel ya abierto (p. ej. al cambiar la selección).
    func setURLs(_ urls: [URL]) {
        previewURLs = urls
        guard QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared() else { return }
        if panel.currentPreviewItemIndex >= urls.count {
            panel.currentPreviewItemIndex = max(0, urls.count - 1)
        }
        panel.reloadData()
    }

    func close() {
        guard QLPreviewPanel.sharedPreviewPanelExists() else { return }
        QLPreviewPanel.shared()?.orderOut(nil)
    }

    // MARK: - QLPreviewPanelDataSource

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewURLs.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard index >= 0, index < previewURLs.count else { return nil }
        return previewURLs[index] as NSURL
    }

    // MARK: - QLPreviewPanelDelegate

    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        false
    }
}

/// El panel de QuickLook exige que algún objeto de la cadena de respondedores acepte su control;
/// el delegate de la app es el último eslabón de esa cadena.
extension J4IAppDelegate: QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        !QuickLookController.shared.previewURLs.isEmpty
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        QuickLookController.shared.previewURLs.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        let urls = QuickLookController.shared.previewURLs
        guard index >= 0, index < urls.count else { return nil }
        return urls[index] as NSURL
    }
}
