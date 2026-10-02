import AppKit

/// Cosas de la app que sólo se pueden hacer desde AppKit.
///
/// Lo principal es el menú del **clic derecho sobre el icono del Dock**: la lista de subapps
/// para levantar la que quieras, sin abrir antes la ventana.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Título de la primera línea del menú del Dock (es informativa, no se puede pulsar).
    static let dockMenuHeader = "Levantar una app"

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()

        let header = NSMenuItem(title: Self.dockMenuHeader, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        for (index, app) in SubAppsCatalog.items.enumerated() {
            menu.addItem(subAppItem(for: app, index: index))
        }

        menu.addItem(.separator())
        let hubItem = NSMenuItem(title: "Abrir JUST4ALL", action: #selector(showHub(_:)), keyEquivalent: "")
        hubItem.target = self
        menu.addItem(hubItem)

        return menu
    }

    /// Una línea del menú por subapp. El índice viaja en `tag`: así el menú no tiene que
    /// saber nada de la subapp, sólo devolvérnosla a la acción.
    private func subAppItem(for app: SubApp, index: Int) -> NSMenuItem {
        let item = NSMenuItem(title: app.name, action: #selector(openSubApp(_:)), keyEquivalent: "")
        item.target = self
        item.tag = index
        item.image = NSImage(systemSymbolName: app.systemIcon, accessibilityDescription: nil)
        item.toolTip = app.subtitle
        return item
    }

    @objc func openSubApp(_ sender: NSMenuItem) {
        let apps = SubAppsCatalog.items
        guard apps.indices.contains(sender.tag) else { return }
        SubAppLauncher.open(apps[sender.tag])
    }

    @objc func showHub(_ sender: Any?) {
        SubAppLauncher.revealMainWindow()
    }
}
