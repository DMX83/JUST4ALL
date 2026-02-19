import AppKit
import Foundation
import J4FFileSystem
import J4FOps
import UniformTypeIdentifiers

extension Notification.Name {
    static let j4fFocusPathBar = Notification.Name("j4f.focusPathBar")
}

private enum PanelSide: String {
    case left = "Izquierdo"
    case right = "Derecho"
}

private struct FileRow {
    let url: URL
    let name: String
    let isDirectory: Bool
    let sizeBytes: Int64?
    let modifiedDate: Date?
    let typeDescription: String

    var sizeDisplay: String {
        guard let sizeBytes else { return "--" }
        return ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    var modifiedDisplay: String {
        guard let modifiedDate else { return "--" }
        return Self.dateFormatter.string(from: modifiedDate)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

private final class DirectoryTreeNode {
    let url: URL
    var children: [DirectoryTreeNode] = []
    var isLoaded = false

    init(url: URL) {
        self.url = url
    }
}

private let sharedMetadataCache = URLMetadataLRUCache(capacity: 20_000)

private final class FileIconCache {
    private let lock = NSLock()
    private let cache = NSCache<NSString, NSImage>()
    private let workspace = NSWorkspace.shared

    init() {
        cache.countLimit = 512
    }

    func icon(for row: FileRow) -> NSImage {
        let key = cacheKey(for: row) as NSString

        lock.lock()
        if let cached = cache.object(forKey: key) {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let image: NSImage
        if row.isDirectory {
            image = workspace.icon(for: .folder)
        } else {
            let ext = row.url.pathExtension
            let type = UTType(filenameExtension: ext) ?? .data
            image = workspace.icon(for: type)
        }
        image.size = NSSize(width: 16, height: 16)

        lock.lock()
        cache.setObject(image, forKey: key)
        lock.unlock()

        return image
    }

    private func cacheKey(for row: FileRow) -> String {
        if row.isDirectory { return "__dir__" }
        let ext = row.url.pathExtension.lowercased()
        return ext.isEmpty ? "__file__" : ext
    }
}

private let sharedFileIconCache = FileIconCache()

final class CommanderViewController: NSViewController, NSToolbarDelegate, NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate, NSToolbarItemValidation {
    private enum ToolbarID {
        static let root = NSToolbar.Identifier("j4f.toolbar.main")
        static let back = NSToolbarItem.Identifier("j4f.toolbar.back")
        static let forward = NSToolbarItem.Identifier("j4f.toolbar.forward")
        static let newTab = NSToolbarItem.Identifier("j4f.toolbar.newTab")
        static let copy = NSToolbarItem.Identifier("j4f.toolbar.copy")
        static let move = NSToolbarItem.Identifier("j4f.toolbar.move")
        static let delete = NSToolbarItem.Identifier("j4f.toolbar.delete")
        static let mkdir = NSToolbarItem.Identifier("j4f.toolbar.mkdir")
        static let rename = NSToolbarItem.Identifier("j4f.toolbar.rename")
        static let deletePermanent = NSToolbarItem.Identifier("j4f.toolbar.deletePermanent")
        static let addLocation = NSToolbarItem.Identifier("j4f.toolbar.addLocation")
        static let tasks = NSToolbarItem.Identifier("j4f.toolbar.tasks")
        static let refresh = NSToolbarItem.Identifier("j4f.toolbar.refresh")
        static let diagnostics = NSToolbarItem.Identifier("j4f.toolbar.diagnostics")
        static let infoCurrent = NSToolbarItem.Identifier("j4f.toolbar.infoCurrent")
        static let search = NSToolbarItem.Identifier("j4f.toolbar.search")
    }

    private let leftPanel = FilePanelViewController(side: .left)
    private let rightPanel = FilePanelViewController(side: .right)
    private let bookmarkStore = SecurityScopedBookmarkStore()
    private let favoriteStore = FavoriteLocationStore()
    private let recentStore = RecentLocationStore()
    private let jobQueue = JobQueueService()
    private let leftWatcher = DirectoryWatchService()
    private let rightWatcher = DirectoryWatchService()
    private let diagnosticsExporter = DiagnosticsExporter()
    private var taskManagerWindow: TaskManagerWindowController?

    private var activeSide: PanelSide = .left {
        didSet {
            updateActiveIndicator()
        }
    }

    private let activeIndicatorLabel = NSTextField(labelWithString: "Panel activo: Izquierdo")
    private let pathField = NSTextField(string: "")
    private let statusLabel = NSTextField(labelWithString: "Listo")
    private let volumeWarningLabel = NSTextField(labelWithString: "")
    private let searchField = NSSearchField()
    private let directoryTree = NSOutlineView()
    private var toolbarConfigured = false
    private let authorizedTable = NSTableView()
    private let favoritesTable = NSTableView()
    private let recentsTable = NSTableView()
    private let reauthTable = NSTableView()
    private var authorizedLocations: [URL] = []
    private var favoriteLocations: [URL] = []
    private var recentLocations: [URL] = []
    private var failedBookmarks: [BookmarkedLocation] = []
    private var scopedAccessCounts: [String: Int] = [:]
    private var keyMonitor: Any?
    private var activeJobIds: Set<UUID> = []
    private var preferences = J4FPreferences.load()
    private var directoryTreeRoot: DirectoryTreeNode?

    override func loadView() {
        view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureLayout()
        configureCallbacks()
        applyPreferences(initial: true)
        loadSidebarLocations()
        updatePathFieldFromActivePanel()
        reloadDirectoryTree(root: activePanel.currentDirectoryURL)
        NotificationCenter.default.addObserver(self, selector: #selector(focusPathBar), name: .j4fFocusPathBar, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onPreferencesChanged), name: .j4fPreferencesChanged, object: nil)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        configureToolbarIfNeeded()
        installKeyMonitorIfNeeded()
    }

    deinit {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        leftWatcher.stop()
        rightWatcher.stop()
        stopAllScopedAccess()
        NotificationCenter.default.removeObserver(self)
    }

    private func configureLayout() {
        let topBar = NSStackView()
        topBar.orientation = .horizontal
        topBar.spacing = 8
        topBar.translatesAutoresizingMaskIntoConstraints = false

        activeIndicatorLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        activeIndicatorLabel.setAccessibilityLabel("Panel activo")
        pathField.placeholderString = "Ruta (Cmd+L)"
        pathField.isEditable = true
        pathField.isSelectable = true
        pathField.isBezeled = true
        pathField.target = self
        pathField.action = #selector(commitPathField)
        pathField.setAccessibilityLabel("Barra de ruta")

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.setAccessibilityLabel("Estado")
        volumeWarningLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        volumeWarningLabel.textColor = .systemOrange
        volumeWarningLabel.isHidden = true
        volumeWarningLabel.setAccessibilityLabel("Advertencia de volumen")

        let pathGoButton = NSButton(title: "Go", target: self, action: #selector(commitPathField))
        pathGoButton.bezelStyle = .rounded
        pathGoButton.setAccessibilityLabel("Ir a la ruta")

        topBar.addArrangedSubview(activeIndicatorLabel)
        topBar.addArrangedSubview(pathField)
        topBar.addArrangedSubview(pathGoButton)

        let panelsSplit = NSSplitView()
        panelsSplit.translatesAutoresizingMaskIntoConstraints = false
        panelsSplit.isVertical = true
        panelsSplit.dividerStyle = .thin

        addChild(leftPanel)
        addChild(rightPanel)
        panelsSplit.addArrangedSubview(leftPanel.view)
        panelsSplit.addArrangedSubview(rightPanel.view)

        let sidebarView = makeSidebarView()

        let bodySplit = NSSplitView()
        bodySplit.translatesAutoresizingMaskIntoConstraints = false
        bodySplit.isVertical = true
        bodySplit.dividerStyle = .thin
        bodySplit.addArrangedSubview(sidebarView)
        bodySplit.addArrangedSubview(panelsSplit)
        sidebarView.widthAnchor.constraint(equalToConstant: 250).isActive = true

        let container = NSStackView()
        container.orientation = .vertical
        container.spacing = 10
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addArrangedSubview(topBar)
        container.addArrangedSubview(bodySplit)
        container.addArrangedSubview(volumeWarningLabel)
        container.addArrangedSubview(statusLabel)

        view.addSubview(container)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            container.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            bodySplit.heightAnchor.constraint(greaterThanOrEqualToConstant: 420),
            pathField.widthAnchor.constraint(greaterThanOrEqualToConstant: 280)
        ])
    }

    private func makeSidebarView() -> NSView {
        let container = NSStackView()
        container.orientation = .vertical
        container.spacing = 8
        container.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.cornerRadius = 8
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor.separatorColor.cgColor

        let header = NSTextField(labelWithString: "Arbol")
        header.font = .systemFont(ofSize: 12, weight: .semibold)

        let addLocationButton = NSButton(title: "Anadir ubicacion", target: self, action: #selector(addAuthorizedLocation))
        addLocationButton.bezelStyle = .rounded
        addLocationButton.font = .systemFont(ofSize: 11)
        addLocationButton.setAccessibilityLabel("Autorizar ubicacion para sandbox")

        let infoCurrentButton = NSButton(title: "Info carpeta actual", target: self, action: #selector(showCurrentDirectoryInfo))
        infoCurrentButton.bezelStyle = .rounded
        infoCurrentButton.font = .systemFont(ofSize: 11)
        infoCurrentButton.setAccessibilityLabel("Mostrar informacion de carpeta actual")

        directoryTree.headerView = nil
        directoryTree.selectionHighlightStyle = .regular
        directoryTree.rowSizeStyle = .small
        directoryTree.delegate = self
        directoryTree.dataSource = self
        directoryTree.doubleAction = #selector(openSelectedTreeNode)
        directoryTree.target = self
        directoryTree.setAccessibilityLabel("Arbol del directorio actual")
        if directoryTree.tableColumns.isEmpty {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("tree"))
            col.title = "Carpetas"
            col.width = 220
            directoryTree.addTableColumn(col)
            directoryTree.outlineTableColumn = col
        }
        let treeScroll = NSScrollView()
        treeScroll.documentView = directoryTree
        treeScroll.hasVerticalScroller = true
        treeScroll.translatesAutoresizingMaskIntoConstraints = false
        treeScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 380).isActive = true

        container.addArrangedSubview(header)
        container.addArrangedSubview(addLocationButton)
        container.addArrangedSubview(infoCurrentButton)
        container.addArrangedSubview(treeScroll)

        return container
    }

    private func sidebarSectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func makeTableScroll(for table: NSTableView, accessibilityLabel: String) -> NSScrollView {
        table.headerView = nil
        table.usesAlternatingRowBackgroundColors = false
        table.selectionHighlightStyle = .regular
        table.target = self
        table.doubleAction = #selector(openSelectedSidebarLocation(_:))
        table.dataSource = self
        table.delegate = self
        table.setAccessibilityLabel(accessibilityLabel)

        if table.tableColumns.isEmpty {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("path"))
            col.width = 220
            table.addTableColumn(col)
        }

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: 88).isActive = true
        scroll.setAccessibilityLabel(accessibilityLabel)
        return scroll
    }

    private func configureCallbacks() {
        leftPanel.onActivate = { [weak self] in
            self?.activeSide = .left
            self?.updatePathFieldFromActivePanel()
        }
        rightPanel.onActivate = { [weak self] in
            self?.activeSide = .right
            self?.updatePathFieldFromActivePanel()
        }

        leftPanel.onStatus = { [weak self] text in
            self?.statusLabel.stringValue = text
            self?.updatePathFieldFromActivePanel()
        }
        rightPanel.onStatus = { [weak self] text in
            self?.statusLabel.stringValue = text
            self?.updatePathFieldFromActivePanel()
        }

        leftPanel.onDirectoryChanged = { [weak self] url in
            self?.registerRecent(url: url)
            self?.updateVolumeWarning(for: url)
            self?.updatePathFieldFromActivePanel()
            self?.updateWatcher(for: .left, directory: url)
            if self?.activeSide == .left {
                self?.reloadDirectoryTree(root: url)
            }
        }
        rightPanel.onDirectoryChanged = { [weak self] url in
            self?.registerRecent(url: url)
            self?.updateVolumeWarning(for: url)
            self?.updatePathFieldFromActivePanel()
            self?.updateWatcher(for: .right, directory: url)
            if self?.activeSide == .right {
                self?.reloadDirectoryTree(root: url)
            }
        }

        leftPanel.onPasteRequested = { [weak self] in
            self?.pasteItemsFromClipboardToActivePanel()
        }
        rightPanel.onPasteRequested = { [weak self] in
            self?.pasteItemsFromClipboardToActivePanel()
        }
    }

    @objc private func focusPathBar() {
        view.window?.makeFirstResponder(pathField)
        pathField.currentEditor()?.selectAll(nil)
    }

    @objc private func commitPathField() {
        activePanel.openPath(pathField.stringValue)
    }

    @objc private func goBack() {
        activePanel.goBack()
    }

    @objc private func goForward() {
        activePanel.goForward()
    }

    @objc private func newTab() {
        activePanel.newTab()
        statusLabel.stringValue = "Nueva tab en panel \(activeSide.rawValue)."
    }

    @objc private func closeTabOrWindow() {
        if activePanel.closeCurrentTab() {
            statusLabel.stringValue = "Tab cerrada en panel \(activeSide.rawValue)."
        } else {
            statusLabel.stringValue = "No hay mas tabs para cerrar; cerrando ventana."
            view.window?.performClose(nil)
        }
    }

    @objc private func copySelection() {
        let selected = activePanel.selectedURLs()
        guard !selected.isEmpty else {
            statusLabel.stringValue = "No hay seleccion para copiar."
            return
        }

        let destination = inactivePanel.currentDirectoryURL
        if shouldUseSystemCopy(sources: selected, destination: destination) {
            runSystemCopy(sources: selected, destination: destination)
            return
        }
        enqueueFileJob(type: .copy, selected: selected, destination: destination)
    }

    @objc private func moveSelection() {
        let selected = activePanel.selectedURLs()
        guard !selected.isEmpty else {
            statusLabel.stringValue = "No hay seleccion para mover."
            return
        }

        let destination = inactivePanel.currentDirectoryURL
        enqueueFileJob(type: .move, selected: selected, destination: destination)
    }

    @objc private func deleteSelection() {
        let selected = activePanel.selectedURLs()
        let count = selected.count
        guard count > 0 else {
            statusLabel.stringValue = "No hay seleccion para borrar."
            return
        }

        if preferences.deleteBehavior == .permanent {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Eliminar definitivamente \(count) elemento(s)"
            alert.informativeText = "Preferencia activa: eliminacion definitiva."
            alert.addButton(withTitle: "Eliminar")
            alert.addButton(withTitle: "Cancelar")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            enqueueDeleteJob(selected: selected, mode: .deletePermanent, preference: .permanent)
            return
        }

        enqueueDeleteJob(selected: selected, mode: .deleteTrash, preference: .trashIfPossible)
    }

    @objc private func createDirectory() {
        guard let name = promptForText(
            title: "Nueva carpeta",
            message: "Nombre de la carpeta a crear en la ruta actual.",
            defaultValue: "Nueva carpeta"
        ) else {
            return
        }

        do {
            try activePanel.createDirectory(named: name)
            statusLabel.stringValue = "Carpeta creada: \(name)"
        } catch {
            statusLabel.stringValue = "No se pudo crear la carpeta: \(error.localizedDescription)"
            NSSound.beep()
        }
    }

    @objc private func renameSelection() {
        let selected = activePanel.selectedURLs()
        guard selected.count == 1, let source = selected.first else {
            statusLabel.stringValue = "Selecciona un unico elemento para renombrar."
            NSSound.beep()
            return
        }

        let currentName = source.lastPathComponent
        guard let newName = promptForText(
            title: "Renombrar",
            message: "Nuevo nombre para '\(currentName)'.",
            defaultValue: currentName
        ) else {
            return
        }

        do {
            try activePanel.renameItem(at: source, to: newName)
            statusLabel.stringValue = "Renombrado: \(currentName) -> \(newName)"
        } catch {
            statusLabel.stringValue = "No se pudo renombrar: \(error.localizedDescription)"
            NSSound.beep()
        }
    }

    @objc private func deleteSelectionPermanently() {
        let selected = activePanel.selectedURLs()
        let count = selected.count
        guard count > 0 else {
            statusLabel.stringValue = "No hay seleccion para borrar definitivamente."
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Eliminar definitivamente \(count) elemento(s)"
        alert.informativeText = "Esta accion no envia a la Papelera y no se puede deshacer."
        alert.addButton(withTitle: "Eliminar")
        alert.addButton(withTitle: "Cancelar")

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        enqueueDeleteJob(selected: selected, mode: .deletePermanent, preference: .permanent)
    }

    private func enqueueFileJob(type: JobType, selected: [URL], destination: URL) {
        let items = selected.map { JobItem(source: $0, destinationDirectory: destination) }
        let options = JobExecutionOptions(deletePreference: preferences.deleteBehavior.deletePreference)
        var jobId = UUID()
        jobId = jobQueue.enqueue(type: type, items: items, conflictPolicy: .rename, options: options) { [weak self] snapshot in
            guard let self else { return }
            self.updateWatcherPauseState(jobId: jobId, state: snapshot.state)
            let pct = Int(snapshot.progress * 100)
            let bytesPart: String
            if snapshot.totalBytes > 0 {
                let done = ByteCountFormatter.string(fromByteCount: snapshot.processedBytes, countStyle: .file)
                let total = ByteCountFormatter.string(fromByteCount: snapshot.totalBytes, countStyle: .file)
                bytesPart = " | \(done)/\(total)"
            } else {
                bytesPart = ""
            }
            self.statusLabel.stringValue = "[\(snapshot.type.rawValue.uppercased())] \(snapshot.processedItems)/\(snapshot.totalItems) (\(pct)%)\(bytesPart) - \(snapshot.state.rawValue)"
            if snapshot.state == .done || snapshot.state == .failed || snapshot.state == .cancelled {
                self.leftPanel.refreshCurrentDirectory()
                self.rightPanel.refreshCurrentDirectory()
            }
        }
        statusLabel.stringValue = "Job en cola (\(type.rawValue)): \(jobId.uuidString.prefix(8))"
    }

    private func enqueueDeleteJob(selected: [URL], mode: JobType, preference: DeletePreference) {
        let items = selected.map { JobItem(source: $0) }
        let options = JobExecutionOptions(deletePreference: preference)
        var jobId = UUID()
        jobId = jobQueue.enqueue(type: mode, items: items, options: options) { [weak self] snapshot in
            guard let self else { return }
            self.updateWatcherPauseState(jobId: jobId, state: snapshot.state)
            let pct = Int(snapshot.progress * 100)
            self.statusLabel.stringValue = "[DELETE] \(snapshot.processedItems)/\(snapshot.totalItems) (\(pct)%) - \(snapshot.state.rawValue)"
            if snapshot.state == .done || snapshot.state == .failed || snapshot.state == .cancelled {
                self.leftPanel.refreshCurrentDirectory()
                self.rightPanel.refreshCurrentDirectory()
            }
        }
        statusLabel.stringValue = "Job en cola (\(mode.rawValue)): \(jobId.uuidString.prefix(8))"
    }

    @objc private func addAuthorizedLocation() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Autorizar"
        panel.message = "Selecciona una carpeta para autorizar su acceso en sandbox."

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try bookmarkStore.save(url: url)
            _ = beginSecurityScope(for: url)
            loadSidebarLocations()
            statusLabel.stringValue = "Ubicacion autorizada guardada: \(url.lastPathComponent)"
        } catch {
            statusLabel.stringValue = "Error al guardar bookmark: \(error.localizedDescription)"
            NSSound.beep()
        }
    }

    @objc private func searchChanged(_ sender: NSSearchField) {
        activePanel.setSearchQuery(sender.stringValue)
    }

    @objc private func manualRefresh() {
        activePanel.refreshCurrentDirectory()
        statusLabel.stringValue = "Refresh manual completado."
    }

    @objc private func exportDiagnostics() {
        do {
            let result = try diagnosticsExporter.createArchive(
                statusText: statusLabel.stringValue,
                leftPath: leftPanel.currentPath,
                rightPath: rightPanel.currentPath
            )

            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [.zip]
            savePanel.nameFieldStringValue = result.archiveURL.lastPathComponent
            savePanel.canCreateDirectories = true
            savePanel.title = "Exportar diagnostico"
            savePanel.message = "Guarda el archivo zip con informacion de diagnostico."

            guard savePanel.runModal() == .OK, let destination = savePanel.url else {
                try? FileManager.default.removeItem(at: result.archiveURL)
                try? FileManager.default.removeItem(at: result.tempDirectoryURL)
                return
            }

            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: result.archiveURL, to: destination)
            try? FileManager.default.removeItem(at: result.tempDirectoryURL)
            statusLabel.stringValue = "Diagnostico exportado: \(destination.lastPathComponent)"
        } catch {
            statusLabel.stringValue = "No se pudo exportar diagnostico: \(error.localizedDescription)"
            NSSound.beep()
        }
    }

    @objc private func openTaskManager() {
        if taskManagerWindow == nil {
            taskManagerWindow = TaskManagerWindowController(jobQueue: jobQueue)
        }
        taskManagerWindow?.showAndFocus()
    }

    @objc private func addCurrentPathToFavorites() {
        let path = activePanel.currentPath
        favoriteStore.add(path: path)
        favoriteLocations = favoriteStore.list().map { URL(fileURLWithPath: $0) }
        favoritesTable.reloadData()
        statusLabel.stringValue = "Favorito agregado: \(URL(fileURLWithPath: path).lastPathComponent)"
    }

    @objc private func removeSelectedFavorite() {
        let row = favoritesTable.selectedRow
        guard row >= 0, let url = favoriteLocations[safe: row] else {
            statusLabel.stringValue = "Selecciona un favorito para quitar."
            return
        }
        favoriteStore.remove(path: url.path)
        favoriteLocations = favoriteStore.list().map { URL(fileURLWithPath: $0) }
        favoritesTable.reloadData()
        statusLabel.stringValue = "Favorito removido: \(url.lastPathComponent)"
    }

    @objc private func removeSelectedRecent() {
        let row = recentsTable.selectedRow
        guard row >= 0, let url = recentLocations[safe: row] else {
            statusLabel.stringValue = "Selecciona un reciente para quitar."
            return
        }
        recentStore.remove(path: url.path)
        recentLocations = recentStore.list().map { URL(fileURLWithPath: $0) }
        recentsTable.reloadData()
        statusLabel.stringValue = "Reciente removido: \(url.lastPathComponent)"
    }

    @objc private func clearRecentLocations() {
        recentStore.clear()
        recentLocations.removeAll()
        recentsTable.reloadData()
        statusLabel.stringValue = "Recientes limpiados."
    }

    @objc private func openSelectedSidebarLocation(_ sender: NSTableView) {
        let row = sender.clickedRow >= 0 ? sender.clickedRow : sender.selectedRow
        guard row >= 0 else { return }

        let url: URL?
        if sender == authorizedTable {
            url = authorizedLocations[safe: row]
        } else if sender == favoritesTable {
            url = favoriteLocations[safe: row]
        } else if sender == reauthTable {
            if let path = failedBookmarks[safe: row]?.path, !path.isEmpty {
                url = URL(fileURLWithPath: path)
            } else {
                url = nil
            }
        } else {
            url = recentLocations[safe: row]
        }

        guard let target = url else { return }
        _ = beginSecurityScope(for: target)
        activePanel.openURL(target)
    }

    private func loadSidebarLocations() {
        favoriteLocations = favoriteStore.list().map { URL(fileURLWithPath: $0) }
        recentLocations = recentStore.list().map { URL(fileURLWithPath: $0) }
        let report = bookmarkStore.resolveReport()
        authorizedLocations = report.resolvedURLs
        failedBookmarks = report.failedLocations
        for url in authorizedLocations {
            _ = beginSecurityScope(for: url)
        }
        authorizedTable.reloadData()
        favoritesTable.reloadData()
        recentsTable.reloadData()
        reauthTable.reloadData()
        updateWatchersForVisibleDirectories()

        if report.refreshedCount > 0 {
            statusLabel.stringValue = "Bookmarks actualizados: \(report.refreshedCount)."
        }
    }

    @objc private func reauthorizeSelectedBookmark() {
        let row = reauthTable.selectedRow
        guard row >= 0, let failed = failedBookmarks[safe: row] else {
            statusLabel.stringValue = "Selecciona una entrada para reautorizar."
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Reautorizar"
        panel.message = "Selecciona la carpeta para restaurar el acceso: \(failed.path)"

        guard panel.runModal() == .OK, let selectedURL = panel.url else { return }
        do {
            try bookmarkStore.replace(path: failed.path, with: selectedURL)
            loadSidebarLocations()
            statusLabel.stringValue = "Reautorizado: \(selectedURL.lastPathComponent)"
        } catch {
            statusLabel.stringValue = "No se pudo reautorizar: \(error.localizedDescription)"
            NSSound.beep()
        }
    }

    private func registerRecent(url: URL) {
        recentStore.add(path: url.path)
        recentLocations = recentStore.list().map { URL(fileURLWithPath: $0) }
        recentsTable.reloadData()
    }

    private func updateVolumeWarning(for url: URL) {
        guard let info = VolumeInspector.inspect(url: url) else {
            volumeWarningLabel.isHidden = true
            volumeWarningLabel.stringValue = ""
            return
        }

        if info.isReadOnly {
            volumeWarningLabel.stringValue = "Volumen en solo lectura (\(info.fileSystemType)). Algunas operaciones de escritura no estaran disponibles."
            volumeWarningLabel.isHidden = false
            return
        }

        if info.isLikelyNTFS {
            volumeWarningLabel.stringValue = "Volumen NTFS detectado. Escritura puede depender de drivers externos."
            volumeWarningLabel.isHidden = false
            return
        }

        volumeWarningLabel.isHidden = true
        volumeWarningLabel.stringValue = ""
    }

    @discardableResult
    private func beginSecurityScope(for url: URL) -> Bool {
        let key = url.standardizedFileURL.path
        if let count = scopedAccessCounts[key] {
            scopedAccessCounts[key] = count + 1
            return true
        }
        let ok = url.startAccessingSecurityScopedResource()
        if ok {
            scopedAccessCounts[key] = 1
        }
        return ok
    }

    private func stopAllScopedAccess() {
        for (path, count) in scopedAccessCounts {
            let url = URL(fileURLWithPath: path)
            for _ in 0..<count {
                url.stopAccessingSecurityScopedResource()
            }
        }
        scopedAccessCounts.removeAll()
    }

    private var activePanel: FilePanelViewController {
        activeSide == .left ? leftPanel : rightPanel
    }

    private var inactivePanel: FilePanelViewController {
        activeSide == .left ? rightPanel : leftPanel
    }

    private func updateActiveIndicator() {
        activeIndicatorLabel.stringValue = "Panel activo: \(activeSide.rawValue)"
        leftPanel.setActive(activeSide == .left)
        rightPanel.setActive(activeSide == .right)
    }

    private func updatePathFieldFromActivePanel() {
        pathField.stringValue = activePanel.currentPath
        view.window?.toolbar?.validateVisibleItems()
    }

    private func toggleActivePanel() {
        activeSide = (activeSide == .left) ? .right : .left
        activePanel.focusTable()
        updatePathFieldFromActivePanel()
        reloadDirectoryTree(root: activePanel.currentDirectoryURL)
    }

    private func isURLAuthorizedForWatching(_ url: URL) -> Bool {
        // Local dev runs outside App Sandbox should allow watchers everywhere.
        if ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] == nil {
            return true
        }
        let candidate = url.standardizedFileURL.path
        for authorized in authorizedLocations {
            let base = authorized.standardizedFileURL.path
            if candidate == base || candidate.hasPrefix(base + "/") {
                return true
            }
        }
        return false
    }

    private func updateWatchersForVisibleDirectories() {
        updateWatcher(for: .left, directory: leftPanel.currentDirectoryURL)
        updateWatcher(for: .right, directory: rightPanel.currentDirectoryURL)
    }

    private func updateWatcher(for side: PanelSide, directory: URL) {
        let watcher = (side == .left) ? leftWatcher : rightWatcher

        guard isURLAuthorizedForWatching(directory) else {
            watcher.stop()
            return
        }

        do {
            try watcher.start(url: directory) { [weak self] changedPaths in
                guard let self else { return }
                switch side {
                case .left:
                    self.leftPanel.refreshForChangedPaths(changedPaths)
                case .right:
                    self.rightPanel.refreshForChangedPaths(changedPaths)
                }
            }
            watcher.setPaused(!activeJobIds.isEmpty)
        } catch {
            statusLabel.stringValue = "No se pudo activar watcher para \(directory.lastPathComponent): \(error.localizedDescription)"
        }
    }

    private func updateWatcherPauseState(jobId: UUID, state: JobState) {
        switch state {
        case .running, .paused:
            activeJobIds.insert(jobId)
        case .done, .failed, .cancelled:
            activeJobIds.remove(jobId)
        case .queued:
            break
        }

        let paused = !activeJobIds.isEmpty
        leftWatcher.setPaused(paused)
        rightWatcher.setPaused(paused)
    }

    @objc private func onPreferencesChanged() {
        applyPreferences(initial: false)
    }

    @objc private func showCurrentDirectoryInfo() {
        activePanel.showInfoForCurrentDirectory()
    }

    private func applyPreferences(initial: Bool) {
        preferences = J4FPreferences.load()
        leftPanel.setIncludeHidden(preferences.showHiddenFiles)
        rightPanel.setIncludeHidden(preferences.showHiddenFiles)
        BufferSizer.shared.setPreferredBigBytes(preferences.preferredBigBufferMB * 1024 * 1024)
        reloadDirectoryTree(root: activePanel.currentDirectoryURL)

        if !initial {
            statusLabel.stringValue = "Preferencias aplicadas."
        }
    }

    private func reloadDirectoryTree(root: URL) {
        let rootNode = DirectoryTreeNode(url: root)
        directoryTreeRoot = rootNode
        directoryTree.reloadData()
        if directoryTree.numberOfRows > 0 {
            directoryTree.expandItem(rootNode)
            directoryTree.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    @objc private func openSelectedTreeNode() {
        let row = directoryTree.selectedRow
        guard row >= 0, let node = directoryTree.item(atRow: row) as? DirectoryTreeNode else { return }
        activePanel.openURL(node.url)
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard outlineView == directoryTree else { return 0 }
        if item == nil {
            return directoryTreeRoot == nil ? 0 : 1
        }
        guard let node = item as? DirectoryTreeNode else { return 0 }
        loadChildrenIfNeeded(for: node)
        return node.children.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            return directoryTreeRoot as Any
        }
        guard let node = item as? DirectoryTreeNode else {
            return DirectoryTreeNode(url: activePanel.currentDirectoryURL)
        }
        loadChildrenIfNeeded(for: node)
        return node.children[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard outlineView == directoryTree, let node = item as? DirectoryTreeNode else { return false }
        return hasDirectoryChildren(node.url)
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard outlineView == directoryTree, let node = item as? DirectoryTreeNode else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("TreeCell")
        let cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = identifier

        let label: NSTextField
        if let existing = cell.textField {
            label = existing
        } else {
            label = NSTextField(labelWithString: "")
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.textField = label
            cell.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }

        let base = node.url.lastPathComponent.isEmpty ? node.url.path : node.url.lastPathComponent
        label.stringValue = base
        label.lineBreakMode = .byTruncatingMiddle
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard let outline = notification.object as? NSOutlineView, outline == directoryTree else { return }
        let row = outline.selectedRow
        guard row >= 0, let node = outline.item(atRow: row) as? DirectoryTreeNode else { return }
        activePanel.openURL(node.url)
    }

    private func loadChildrenIfNeeded(for node: DirectoryTreeNode) {
        guard !node.isLoaded else { return }
        node.isLoaded = true
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isHiddenKey]
        guard let entries = try? fm.contentsOfDirectory(at: node.url, includingPropertiesForKeys: Array(keys), options: [.skipsPackageDescendants]) else {
            return
        }
        node.children = entries.compactMap { entry in
            guard let values = try? entry.resourceValues(forKeys: keys), values.isDirectory == true else { return nil }
            if !preferences.showHiddenFiles && values.isHidden == true {
                return nil
            }
            return DirectoryTreeNode(url: entry)
        }.sorted {
            $0.url.lastPathComponent.localizedCaseInsensitiveCompare($1.url.lastPathComponent) == .orderedAscending
        }
    }

    private func hasDirectoryChildren(_ url: URL) -> Bool {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isHiddenKey]
        guard let entries = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: Array(keys), options: [.skipsPackageDescendants]) else {
            return false
        }
        for entry in entries {
            guard let values = try? entry.resourceValues(forKeys: keys), values.isDirectory == true else { continue }
            if !preferences.showHiddenFiles && values.isHidden == true {
                continue
            }
            return true
        }
        return false
    }

    private func installKeyMonitorIfNeeded() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.handleKeyShortcut(event) {
                return nil
            }
            return event
        }
    }

    private func handleKeyShortcut(_ event: NSEvent) -> Bool {
        guard view.window?.isKeyWindow == true else { return false }
        if NSApp.modalWindow != nil || view.window?.attachedSheet != nil {
            return false
        }

        if isEditingTextInput {
            return false
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if flags == [] {
            switch event.keyCode {
            case 36, 76: // Return / Enter
                if openSelectedSidebarIfFocused() {
                    return true
                }
            case 48: // Tab
                if view.window?.firstResponder is NSTextView {
                    return false
                }
                toggleActivePanel()
                return true
            case 96: // F5
                copySelection()
                return true
            case 97: // F6
                moveSelection()
                return true
            case 98: // F7
                createDirectory()
                return true
            case 100: // F8
                deleteSelection()
                return true
            default:
                break
            }
        }

        if flags == [.command], let chars = event.charactersIgnoringModifiers?.lowercased() {
            if chars == "t" {
                newTab()
                return true
            }
            if chars == "w" {
                closeTabOrWindow()
                return true
            }
            if chars == "a" {
                activePanel.selectAllItems()
                return true
            }
            if chars == "v" {
                pasteItemsFromClipboardToActivePanel()
                return true
            }
        }

        return false
    }

    private var isEditingTextInput: Bool {
        guard let firstResponder = view.window?.firstResponder else { return false }
        guard let textView = firstResponder as? NSTextView else { return false }
        return textView.isFieldEditor || textView.enclosingScrollView == nil
    }

    private func pasteItemsFromClipboardToActivePanel() {
        let urls = clipboardFileURLs()
        guard !urls.isEmpty else {
            statusLabel.stringValue = "No hay rutas validas en portapapeles para pegar."
            NSSound.beep()
            return
        }
        let destination = activePanel.currentDirectoryURL
        if shouldUseSystemCopy(sources: urls, destination: destination) {
            runSystemCopy(sources: urls, destination: destination)
            return
        }
        enqueueFileJob(type: .copy, selected: urls, destination: activePanel.currentDirectoryURL)
        statusLabel.stringValue = "Pegando \(urls.count) item(s) en panel \(activeSide.rawValue)..."
    }

    private func clipboardFileURLs() -> [URL] {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            return []
        }

        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let fm = FileManager.default
        return lines
            .map { URL(fileURLWithPath: $0) }
            .filter { fm.fileExists(atPath: $0.path) }
    }

    private func shouldUseSystemCopy(sources: [URL], destination: URL) -> Bool {
        guard !sources.isEmpty else { return false }
        return sources.allSatisfy { source in
            sameVolume(source, destination)
        }
    }

    private func sameVolume(_ lhs: URL, _ rhs: URL) -> Bool {
        let lhsVolume = try? lhs.resourceValues(forKeys: [.volumeURLKey]).volume
        let rhsVolume = try? rhs.resourceValues(forKeys: [.volumeURLKey]).volume
        guard let lhsVolume, let rhsVolume else { return false }
        return lhsVolume.standardizedFileURL.path == rhsVolume.standardizedFileURL.path
    }

    private func isDirectoryURL(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private func runSystemCopy(sources: [URL], destination: URL) {
        statusLabel.stringValue = "Copiando \(sources.count) item(s) en mismo volumen con copia del sistema..."
        let fm = FileManager.default

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var copied = 0
            var failures: [String] = []

            for source in sources {
                let proposed = destination.appendingPathComponent(source.lastPathComponent, isDirectory: self.isDirectoryURL(source))
                let target = self.availableDestination(for: proposed)
                do {
                    try fm.copyItem(at: source, to: target)
                    copied += 1
                } catch {
                    failures.append("\(source.lastPathComponent): \(error.localizedDescription)")
                }
            }

            DispatchQueue.main.async {
                self.leftPanel.refreshCurrentDirectory()
                self.rightPanel.refreshCurrentDirectory()
                if failures.isEmpty {
                    self.statusLabel.stringValue = "Copia sistema completada: \(copied)/\(sources.count)."
                } else {
                    self.statusLabel.stringValue = "Copia parcial: \(copied)/\(sources.count). Error en \(failures.count)."
                    NSSound.beep()
                }
            }
        }
    }

    private func availableDestination(for proposed: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: proposed.path) else { return proposed }
        let base = proposed.deletingPathExtension().lastPathComponent
        let ext = proposed.pathExtension
        var idx = 1
        while true {
            let name = ext.isEmpty ? "\(base)-\(idx)" : "\(base)-\(idx).\(ext)"
            let candidate = proposed.deletingLastPathComponent().appendingPathComponent(name)
            if !fm.fileExists(atPath: candidate.path) {
                return candidate
            }
            idx += 1
        }
    }

    private func openSelectedSidebarIfFocused() -> Bool {
        if firstResponderBelongs(to: authorizedTable) {
            openSelectedSidebarLocation(authorizedTable)
            return true
        }
        if firstResponderBelongs(to: favoritesTable) {
            openSelectedSidebarLocation(favoritesTable)
            return true
        }
        if firstResponderBelongs(to: recentsTable) {
            openSelectedSidebarLocation(recentsTable)
            return true
        }
        if firstResponderBelongs(to: reauthTable) {
            openSelectedSidebarLocation(reauthTable)
            return true
        }
        return false
    }

    private func firstResponderBelongs(to table: NSTableView) -> Bool {
        guard let firstResponder = view.window?.firstResponder else { return false }
        if firstResponder === table { return true }
        guard let firstView = firstResponder as? NSView else { return false }
        return firstView.isDescendant(of: table)
    }

    private func configureToolbarIfNeeded() {
        guard let window = view.window, !toolbarConfigured else { return }
        let toolbar = NSToolbar(identifier: ToolbarID.root)
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        toolbarConfigured = true
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            ToolbarID.back, ToolbarID.forward, .flexibleSpace,
            ToolbarID.newTab, ToolbarID.copy, ToolbarID.move, ToolbarID.delete,
            ToolbarID.mkdir, ToolbarID.rename, ToolbarID.deletePermanent,
            .flexibleSpace, ToolbarID.refresh, ToolbarID.infoCurrent, ToolbarID.tasks, ToolbarID.diagnostics, ToolbarID.addLocation, ToolbarID.search
        ]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarAllowedItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        switch itemIdentifier {
        case ToolbarID.back:
            item.label = "Back"
            item.toolTip = "Volver (panel activo)"
            item.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(goBack)
        case ToolbarID.forward:
            item.label = "Forward"
            item.toolTip = "Adelante (panel activo)"
            item.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(goForward)
        case ToolbarID.newTab:
            item.label = "New Tab"
            item.toolTip = "Nueva tab (Cmd+T)"
            item.image = NSImage(systemSymbolName: "plus.square.on.square", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(newTab)
        case ToolbarID.copy:
            item.label = "Copy"
            item.toolTip = "Copiar al otro panel (F5)"
            item.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(copySelection)
        case ToolbarID.move:
            item.label = "Move"
            item.toolTip = "Mover al otro panel (F6)"
            item.image = NSImage(systemSymbolName: "arrow.right.doc.on.clipboard", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(moveSelection)
        case ToolbarID.delete:
            item.label = "Delete"
            item.toolTip = "Enviar a Papelera (F8)"
            item.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(deleteSelection)
        case ToolbarID.mkdir:
            item.label = "Mkdir"
            item.toolTip = "Crear carpeta (F7)"
            item.image = NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(createDirectory)
        case ToolbarID.rename:
            item.label = "Rename"
            item.toolTip = "Renombrar item seleccionado"
            item.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(renameSelection)
        case ToolbarID.deletePermanent:
            item.label = "Delete Permanent"
            item.toolTip = "Eliminar definitivamente"
            item.image = NSImage(systemSymbolName: "trash.slash", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(deleteSelectionPermanently)
        case ToolbarID.addLocation:
            item.label = "Add Location"
            item.toolTip = "Autorizar nueva ubicacion"
            item.image = NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(addAuthorizedLocation)
        case ToolbarID.tasks:
            item.label = "Tasks"
            item.toolTip = "Abrir Task Manager"
            item.image = NSImage(systemSymbolName: "list.bullet.rectangle", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(openTaskManager)
        case ToolbarID.refresh:
            item.label = "Refresh"
            item.toolTip = "Refrescar panel activo"
            item.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(manualRefresh)
        case ToolbarID.infoCurrent:
            item.label = "Info"
            item.toolTip = "Informacion de carpeta actual"
            item.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(showCurrentDirectoryInfo)
        case ToolbarID.diagnostics:
            item.label = "Diagnostics"
            item.toolTip = "Exportar diagnostico"
            item.image = NSImage(systemSymbolName: "stethoscope", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(exportDiagnostics)
        case ToolbarID.search:
            searchField.placeholderString = "Search"
            searchField.target = self
            searchField.action = #selector(searchChanged(_:))
            searchField.delegate = self
            searchField.sendsWholeSearchString = false
            searchField.sendsSearchStringImmediately = true
            searchField.frame = NSRect(x: 0, y: 0, width: 220, height: 28)
            searchField.setAccessibilityLabel("Busqueda rapida")
            item.view = searchField
        default:
            return nil
        }
        return item
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView == authorizedTable {
            return authorizedLocations.count
        }
        if tableView == favoritesTable {
            return favoriteLocations.count
        }
        if tableView == reauthTable {
            return failedBookmarks.count
        }
        return recentLocations.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("SidebarCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = identifier

        let label: NSTextField
        if let existing = cell.textField {
            label = existing
        } else {
            label = NSTextField(labelWithString: "")
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.textField = label
            cell.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }

        let url: URL?
        if tableView == authorizedTable {
            url = authorizedLocations[safe: row]
        } else if tableView == favoritesTable {
            url = favoriteLocations[safe: row]
        } else if tableView == reauthTable {
            if let path = failedBookmarks[safe: row]?.path, !path.isEmpty {
                url = URL(fileURLWithPath: path)
            } else {
                url = nil
            }
        } else {
            url = recentLocations[safe: row]
        }

        label.stringValue = url?.lastPathComponent.isEmpty == false ? (url?.lastPathComponent ?? "--") : (url?.path ?? "--")
        label.lineBreakMode = .byTruncatingMiddle
        return cell
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        switch item.itemIdentifier {
        case ToolbarID.back:
            return activePanel.canGoBack
        case ToolbarID.forward:
            return activePanel.canGoForward
        case ToolbarID.copy, ToolbarID.move, ToolbarID.delete:
            return !activePanel.selectedURLs().isEmpty
        case ToolbarID.rename:
            return activePanel.selectedURLs().count == 1
        case ToolbarID.deletePermanent:
            return !activePanel.selectedURLs().isEmpty
        default:
            return true
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSSearchField, field == searchField else { return }
        activePanel.setSearchQuery(field.stringValue)
    }

    private func promptForText(title: String, message: String, defaultValue: String) -> String? {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Aceptar")
        alert.addButton(withTitle: "Cancelar")

        let input = NSTextField(string: defaultValue)
        input.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        alert.accessoryView = input
        let alertWindow = alert.window
        alertWindow.initialFirstResponder = input
        _ = alertWindow.makeFirstResponder(input)
        input.selectText(nil)

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }
        let value = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

private final class FilePanelViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
    var onActivate: (() -> Void)?
    var onStatus: ((String) -> Void)?
    var onDirectoryChanged: ((URL) -> Void)?
    var onPasteRequested: (() -> Void)?

    private let side: PanelSide
    private let tableView = FocusAwareTableView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let rowCountLabel = NSTextField(labelWithString: "")
    private let tabsControl = NSSegmentedControl()

    private var allRows: [FileRow] = []
    private var rows: [FileRow] = []
    private var loadTask: Task<Void, Never>?
    private var loadToken = UUID()
    private var pendingRefreshWorkItem: DispatchWorkItem?
    private var tabURLs: [URL] = []
    private var activeTabIndex = 0
    private var rootSelected = false

    private var historyBack: [URL] = []
    private var historyForward: [URL] = []
    private(set) var currentURL: URL
    private var sortColumn: String = "name"
    private var ascending = true
    private var searchQuery: String = ""
    private var includeHiddenFiles = false

    var currentPath: String { currentURL.path }
    var currentDirectoryURL: URL { currentURL }
    var canGoBack: Bool { !historyBack.isEmpty }
    var canGoForward: Bool { !historyForward.isEmpty }

    init(side: PanelSide) {
        self.side = side
        self.currentURL = FileManager.default.homeDirectoryForCurrentUser
        self.tabURLs = [FileManager.default.homeDirectoryForCurrentUser]
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureUI()
        loadDirectory(currentURL, pushHistory: false)
    }

    func setActive(_ isActive: Bool) {
        view.layer?.borderColor = isActive ? NSColor.controlAccentColor.cgColor : NSColor.separatorColor.cgColor
        view.layer?.borderWidth = isActive ? 2 : 1
    }

    func openPath(_ path: String) {
        let clean = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            onStatus?("Ruta vacia.")
            NSSound.beep()
            return
        }
        let expanded = NSString(string: clean).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded).standardizedFileURL

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            onStatus?("Ruta invalida o no es carpeta: \(clean)")
            NSSound.beep()
            return
        }
        loadDirectory(url, pushHistory: true)
    }

    func openURL(_ url: URL) {
        let normalized = url.standardizedFileURL
        guard isDirectory(normalized) else {
            onStatus?("Ruta invalida o no es carpeta: \(url.path)")
            NSSound.beep()
            return
        }
        loadDirectory(normalized, pushHistory: true)
    }

    func goBack() {
        guard let previous = historyBack.popLast() else { return }
        historyForward.append(currentURL)
        loadDirectory(previous, pushHistory: false)
    }

    func goForward() {
        guard let next = historyForward.popLast() else { return }
        historyBack.append(currentURL)
        loadDirectory(next, pushHistory: false)
    }

    func setSearchQuery(_ query: String) {
        searchQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        applySortAndReload()
    }

    func selectedURLs() -> [URL] {
        let selected = Array(tableView.selectedRowIndexes).compactMap { (idx: Int) -> URL? in
            guard idx >= 0, idx < rows.count else { return nil }
            return rows[idx].url
        }
        if !selected.isEmpty {
            return selected
        }
        return rootSelected ? [currentURL] : []
    }

    func deleteSelectedToTrash() -> Int {
        let selected = selectedURLs()
        guard !selected.isEmpty else { return 0 }
        var deleted = 0
        for url in selected {
            do {
                var resulting: NSURL?
                try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
                deleted += 1
            } catch {
                onStatus?("No se pudo borrar \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        loadDirectory(currentURL, pushHistory: false)
        return deleted
    }

    func createDirectory(named name: String) throws {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw NSError(domain: "JUST4FOLDERS", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Nombre de carpeta vacio."]) }
        let target = currentURL.appendingPathComponent(clean, isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        loadDirectory(currentURL, pushHistory: false)
    }

    func renameSelected(to newName: String) throws {
        let selected = selectedURLs()
        guard selected.count == 1, let source = selected.first else {
            throw NSError(domain: "JUST4FOLDERS", code: 1002, userInfo: [NSLocalizedDescriptionKey: "Selecciona un unico elemento para renombrar."])
        }
        try renameItem(at: source, to: newName)
    }

    func renameItem(at source: URL, to newName: String) throws {
        let clean = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            throw NSError(domain: "JUST4FOLDERS", code: 1003, userInfo: [NSLocalizedDescriptionKey: "Nuevo nombre vacio."])
        }
        let destination = source.deletingLastPathComponent().appendingPathComponent(clean, isDirectory: isDirectory(source))
        if source.standardizedFileURL.path == destination.standardizedFileURL.path {
            return
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            throw NSError(domain: "JUST4FOLDERS", code: 1004, userInfo: [NSLocalizedDescriptionKey: "Ya existe un elemento con ese nombre."])
        }
        try FileManager.default.moveItem(at: source, to: destination)
        loadDirectory(currentURL, pushHistory: false)
    }

    func deleteSelectedPermanently() -> Int {
        let selected = selectedURLs()
        guard !selected.isEmpty else { return 0 }
        var deleted = 0
        for url in selected {
            do {
                try FileManager.default.removeItem(at: url)
                deleted += 1
            } catch {
                onStatus?("No se pudo eliminar \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        loadDirectory(currentURL, pushHistory: false)
        return deleted
    }

    func refreshCurrentDirectory() {
        loadDirectory(currentURL, pushHistory: false)
    }

    func setIncludeHidden(_ includeHidden: Bool) {
        guard includeHiddenFiles != includeHidden else { return }
        includeHiddenFiles = includeHidden
        loadDirectory(currentURL, pushHistory: false)
    }

    func refreshForChangedPaths(_ changedPaths: [String]) {
        guard !changedPaths.isEmpty else { return }

        let normalizedRoot = currentURL.standardizedFileURL.path
        var needsFullReload = false
        var childPaths: Set<String> = []

        for raw in changedPaths {
            let changed = URL(fileURLWithPath: raw).standardizedFileURL.path
            guard changed == normalizedRoot || changed.hasPrefix(normalizedRoot + "/") else { continue }

            if changed == normalizedRoot {
                needsFullReload = true
                continue
            }

            let relative = String(changed.dropFirst(normalizedRoot.count + 1))
            guard !relative.isEmpty else { continue }
            guard let firstComponent = relative.split(separator: "/").first else { continue }
            let child = currentURL.appendingPathComponent(String(firstComponent)).standardizedFileURL.path
            childPaths.insert(child)
        }

        if needsFullReload && childPaths.isEmpty {
            // Root-only events are often metadata noise; skip hard reload to avoid flicker.
            return
        }

        if needsFullReload || childPaths.count > 64 {
            loadDirectory(currentURL, pushHistory: false)
            return
        }

        var rowMap: [String: FileRow] = [:]
        for row in allRows {
            rowMap[row.url.standardizedFileURL.path] = row
        }

        for childPath in childPaths {
            let childURL = URL(fileURLWithPath: childPath)
            if !FileManager.default.fileExists(atPath: childPath) {
                rowMap.removeValue(forKey: childPath)
                continue
            }
            if !includeHiddenFiles && childURL.lastPathComponent.hasPrefix(".") {
                rowMap.removeValue(forKey: childPath)
                continue
            }
            if let updated = buildRow(for: childURL) {
                rowMap[childPath] = updated
            }
        }

        allRows = Array(rowMap.values)
        applySortAndReload()
        onStatus?("Actualizado por watcher (\(childPaths.count) cambio(s)).")
    }

    func focusTable() {
        view.window?.makeFirstResponder(tableView)
    }

    func selectAllItems() {
        guard !rows.isEmpty else { return }
        tableView.selectRowIndexes(IndexSet(integersIn: 0..<rows.count), byExtendingSelection: false)
        activatePanel()
    }

    @discardableResult
    func pasteItemsFromClipboard() throws -> Int {
        let pb = NSPasteboard.general
        guard let text = pb.string(forType: .string), !text.isEmpty else { return 0 }

        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return 0 }

        let fm = FileManager.default
        var pasted = 0
        for line in lines {
            let src = URL(fileURLWithPath: line)
            guard fm.fileExists(atPath: src.path) else { continue }
            let proposed = currentURL.appendingPathComponent(src.lastPathComponent, isDirectory: isDirectory(src))
            let destination = availableDestination(for: proposed)
            do {
                try fm.copyItem(at: src, to: destination)
                pasted += 1
            } catch {
                onStatus?("Error pegando \(src.lastPathComponent): \(error.localizedDescription)")
            }
        }

        if pasted > 0 {
            loadDirectory(currentURL, pushHistory: false)
        }
        return pasted
    }

    func newTab() {
        tabURLs.append(currentURL)
        activeTabIndex = tabURLs.count - 1
        historyBack.removeAll()
        historyForward.removeAll()
        refreshTabsControl()
        loadDirectory(currentURL, pushHistory: false)
    }

    @discardableResult
    func closeCurrentTab() -> Bool {
        guard tabURLs.count > 1 else { return false }
        tabURLs.remove(at: activeTabIndex)
        if activeTabIndex >= tabURLs.count {
            activeTabIndex = max(0, tabURLs.count - 1)
        }
        historyBack.removeAll()
        historyForward.removeAll()
        refreshTabsControl()
        loadDirectory(tabURLs[activeTabIndex], pushHistory: false)
        return true
    }

    private func configureUI() {
        view.wantsLayer = true
        view.layer?.cornerRadius = 8
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor.separatorColor.cgColor
        view.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.stringValue = "Panel \(side.rawValue)"

        rowCountLabel.font = .systemFont(ofSize: 11)
        rowCountLabel.textColor = .secondaryLabelColor

        tabsControl.segmentStyle = .capsule
        tabsControl.target = self
        tabsControl.action = #selector(tabSelectionChanged)
        tabsControl.setAccessibilityLabel("Pestanas del panel \(side.rawValue)")
        refreshTabsControl()

        tableView.focusDelegate = self
        tableView.onEnterPressed = { [weak self] in
            self?.openSelected()
        }
        tableView.onBackgroundClicked = { [weak self] in
            self?.selectRootDirectory()
        }
        tableView.headerView = NSTableHeaderView(frame: .zero)
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.allowsMultipleSelection = true
        tableView.allowsEmptySelection = true
        tableView.delegate = self
        tableView.dataSource = self
        tableView.doubleAction = #selector(openSelected)
        tableView.target = self
        tableView.menu = makeContextMenu()
        tableView.setAccessibilityLabel("Contenido del panel \(side.rawValue)")

        addColumn(id: "name", title: "Nombre", width: 280)
        addColumn(id: "size", title: "Tamano", width: 100)
        addColumn(id: "modified", title: "Modificado", width: 140)
        addColumn(id: "type", title: "Tipo", width: 120)

        tableView.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let header = NSStackView()
        header.orientation = .horizontal
        header.translatesAutoresizingMaskIntoConstraints = false
        header.addArrangedSubview(titleLabel)
        header.addArrangedSubview(NSView())
        header.addArrangedSubview(rowCountLabel)

        let tabsRow = NSStackView()
        tabsRow.orientation = .horizontal
        tabsRow.spacing = 8
        tabsRow.translatesAutoresizingMaskIntoConstraints = false
        tabsRow.addArrangedSubview(tabsControl)
        tabsRow.addArrangedSubview(NSView())

        view.addSubview(header)
        view.addSubview(tabsRow)
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            header.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            tabsRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            tabsRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            tabsRow.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            scrollView.topAnchor.constraint(equalTo: tabsRow.bottomAnchor, constant: 8),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8)
        ])
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu(title: "Acciones")
        menu.delegate = self
        menu.addItem(withTitle: "Abrir", action: #selector(openSelected), keyEquivalent: "")
        menu.addItem(withTitle: "Abrir en Finder", action: #selector(contextOpenInFinder), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Copiar ruta", action: #selector(contextCopyPath), keyEquivalent: "")
        menu.addItem(withTitle: "Pegar item", action: #selector(contextPasteItems), keyEquivalent: "")
        menu.addItem(withTitle: "Informacion", action: #selector(contextShowInfo), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Nueva carpeta", action: #selector(contextCreateFolder), keyEquivalent: "")
        menu.addItem(withTitle: "Renombrar", action: #selector(contextRename), keyEquivalent: "")
        menu.addItem(withTitle: "Eliminar (Papelera)", action: #selector(contextDeleteToTrash), keyEquivalent: "")
        menu.addItem(withTitle: "Eliminar definitivamente", action: #selector(contextDeletePermanent), keyEquivalent: "")
        for item in menu.items {
            item.target = self
        }
        return menu
    }

    private func addColumn(id: String, title: String, width: CGFloat) {
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(rawValue: id))
        col.title = title
        col.width = width
        col.sortDescriptorPrototype = NSSortDescriptor(key: id, ascending: true)
        tableView.addTableColumn(col)
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private func loadDirectory(_ url: URL, pushHistory: Bool) {
        loadTask?.cancel()
        pendingRefreshWorkItem?.cancel()
        loadToken = UUID()

        if pushHistory, url != currentURL {
            historyBack.append(currentURL)
            historyForward.removeAll()
        }

        currentURL = url
        rootSelected = false
        if activeTabIndex < tabURLs.count {
            tabURLs[activeTabIndex] = url
        }
        refreshTabsControl()
        onDirectoryChanged?(url)
        titleLabel.stringValue = "Panel \(side.rawValue) — \(url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent)"
        onStatus?("Cargando \(url.path)...")
        allRows.removeAll(keepingCapacity: true)
        rows.removeAll(keepingCapacity: true)
        tableView.reloadData()
        rowCountLabel.stringValue = "0 items"

        let token = loadToken
        let includeHidden = includeHiddenFiles

        loadTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let total = try DirectoryListingService.listIncremental(
                    folder: url,
                    includeHidden: includeHidden,
                    batchSize: 320,
                    metadataCache: sharedMetadataCache
                ) { batch in
                    Task { @MainActor in
                        guard self.loadToken == token else { return }
                        let mapped = batch.map { entry in
                            FileRow(
                                url: entry.url,
                                name: entry.url.lastPathComponent,
                                isDirectory: entry.isDirectory,
                                sizeBytes: entry.isDirectory ? nil : entry.fileSize,
                                modifiedDate: entry.modifiedDate,
                                typeDescription: entry.localizedTypeDescription ?? (entry.isDirectory ? "Folder" : "Archivo")
                            )
                        }
                        self.allRows.append(contentsOf: mapped)
                        self.scheduleDebouncedRefresh()
                        self.onStatus?("Cargando \(self.allRows.count) elemento(s)...")
                    }
                }

                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard self.loadToken == token else { return }
                    self.pendingRefreshWorkItem?.cancel()
                    self.applySortAndReload()
                    self.onStatus?("\(total) elemento(s) en \(url.path)")
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    guard self.loadToken == token else { return }
                    self.onStatus?("Error cargando carpeta: \(error.localizedDescription)")
                }
            }
        }
    }

    private func buildRow(for url: URL) -> FileRow? {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .localizedTypeDescriptionKey
        ]
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
        guard let isDirectory = values.isDirectory else { return nil }

        let typeDescription = values.localizedTypeDescription ?? (isDirectory ? "Folder" : "Archivo")
        return FileRow(
            url: url,
            name: url.lastPathComponent,
            isDirectory: isDirectory,
            sizeBytes: isDirectory ? nil : Int64(values.fileSize ?? 0),
            modifiedDate: values.contentModificationDate,
            typeDescription: typeDescription
        )
    }

    private func scheduleDebouncedRefresh() {
        pendingRefreshWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.applySortAndReload()
        }
        pendingRefreshWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    @objc private func openSelected() {
        activatePanel()
        let idx = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        guard idx >= 0, idx < rows.count else { return }
        let row = rows[idx]
        if row.isDirectory {
            loadDirectory(row.url, pushHistory: true)
        } else {
            NSWorkspace.shared.open(row.url)
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < rows.count else { return nil }
        let item = rows[row]
        let columnId = tableColumn?.identifier.rawValue ?? "name"
        let text: String

        switch columnId {
        case "name": text = item.name
        case "size": text = item.sizeDisplay
        case "modified": text = item.modifiedDisplay
        case "type": text = item.typeDescription
        default: text = item.name
        }

        let identifier = NSUserInterfaceItemIdentifier("Cell-\(columnId)")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = identifier

        let label: NSTextField
        if let existing = cell.textField {
            label = existing
        } else {
            label = NSTextField(labelWithString: "")
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.textField = label
            cell.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }

        label.stringValue = text
        label.lineBreakMode = .byTruncatingMiddle
        label.textColor = item.isDirectory && columnId == "name" ? .controlAccentColor : .labelColor

        let existingLeadingConstraints = cell.constraints.filter { constraint in
            (constraint.firstItem as? NSTextField) == label && constraint.firstAttribute == .leading
        }
        NSLayoutConstraint.deactivate(existingLeadingConstraints)

        if columnId == "name" {
            let icon: NSImageView
            if let existing = cell.imageView {
                icon = existing
            } else {
                icon = NSImageView(frame: .zero)
                icon.translatesAutoresizingMaskIntoConstraints = false
                cell.imageView = icon
                cell.addSubview(icon)
                NSLayoutConstraint.activate([
                    icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                    icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    icon.widthAnchor.constraint(equalToConstant: 16),
                    icon.heightAnchor.constraint(equalToConstant: 16),
                ])
            }
            icon.isHidden = false
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6)
            ])
            icon.image = sharedFileIconCache.icon(for: item)
        } else {
            cell.imageView?.isHidden = true
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6)
            ])
        }

        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        if !tableView.selectedRowIndexes.isEmpty {
            rootSelected = false
        }
        activatePanel()
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard let descriptor = tableView.sortDescriptors.first else { return }
        sortColumn = descriptor.key ?? "name"
        ascending = descriptor.ascending
        applySortAndReload()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(insertNewline(_:)) {
            openSelected()
            return true
        }
        return false
    }

    private func applySortAndReload() {
        let selectedPaths = Set(selectedURLs().map { $0.standardizedFileURL.path })
        let filtered: [FileRow]
        if searchQuery.isEmpty {
            filtered = allRows
        } else {
            let query = searchQuery.lowercased()
            filtered = allRows.filter { row in
                row.name.lowercased().contains(query) || row.typeDescription.lowercased().contains(query)
            }
        }

        rows = filtered.sorted { lhs, rhs in
            let result: ComparisonResult
            switch sortColumn {
            case "size":
                result = compareOptional(lhs.sizeBytes, rhs.sizeBytes)
            case "modified":
                result = compareOptional(lhs.modifiedDate, rhs.modifiedDate)
            case "type":
                result = lhs.typeDescription.localizedCaseInsensitiveCompare(rhs.typeDescription)
            default:
                if lhs.isDirectory != rhs.isDirectory {
                    result = lhs.isDirectory ? .orderedAscending : .orderedDescending
                } else {
                    result = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                }
            }
            if ascending {
                return result == .orderedAscending
            }
            return result == .orderedDescending
        }

        tableView.reloadData()
        if !selectedPaths.isEmpty {
            let indexes = IndexSet(rows.enumerated().compactMap { idx, row in
                selectedPaths.contains(row.url.standardizedFileURL.path) ? idx : nil
            })
            if !indexes.isEmpty {
                tableView.selectRowIndexes(indexes, byExtendingSelection: false)
            }
        }
        rowCountLabel.stringValue = "\(rows.count) items"
    }

    private func compareOptional<T: Comparable>(_ lhs: T?, _ rhs: T?) -> ComparisonResult {
        switch (lhs, rhs) {
        case let (l?, r?):
            if l == r { return .orderedSame }
            return l < r ? .orderedAscending : .orderedDescending
        case (.none, .none):
            return .orderedSame
        case (.none, .some):
            return .orderedAscending
        case (.some, .none):
            return .orderedDescending
        }
    }

    fileprivate func activatePanel() {
        onActivate?()
    }

    func menuWillOpen(_ menu: NSMenu) {
        activatePanel()
        let clicked = tableView.clickedRow
        let mousePointInTable = tableView.convert(NSEvent.mouseLocation, from: nil)
        let rowAtMouse = tableView.row(at: mousePointInTable)
        let targetRow = clicked >= 0 ? clicked : rowAtMouse
        if targetRow >= 0 && !tableView.selectedRowIndexes.contains(targetRow) {
            tableView.selectRowIndexes(IndexSet(integer: targetRow), byExtendingSelection: false)
            rootSelected = false
        } else if targetRow < 0 {
            selectRootDirectory(announce: false)
        }
    }

    private func selectRootDirectory(announce: Bool = true) {
        rootSelected = true
        tableView.deselectAll(nil)
        activatePanel()
        if announce {
            onStatus?("Raiz seleccionada: \(currentURL.path)")
        }
    }

    @objc private func contextOpenInFinder() {
        let selected = selectedURLs()
        guard !selected.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(selected)
    }

    @objc private func contextCreateFolder() {
        do {
            let createdURL = try createDirectoryWithIncrementalName(baseName: "Nueva carpeta")
            onStatus?("Carpeta creada: \(createdURL.lastPathComponent)")
        } catch {
            onStatus?("No se pudo crear carpeta: \(error.localizedDescription)")
            NSSound.beep()
        }
    }

    @objc private func contextCopyPath() {
        let selected = selectedURLs()
        guard !selected.isEmpty else { return }
        let text = selected.map(\.path).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        onStatus?("Ruta(s) copiada(s): \(selected.count)")
    }

    @objc private func contextPasteItems() {
        if let onPasteRequested {
            onPasteRequested()
            return
        }
        do {
            let pasted = try pasteItemsFromClipboard()
            if pasted > 0 {
                onStatus?("Pegados \(pasted) item(s).")
            } else {
                onStatus?("No hay rutas validas para pegar.")
            }
        } catch {
            onStatus?("No se pudo pegar: \(error.localizedDescription)")
            NSSound.beep()
        }
    }

    @objc private func contextShowInfo() {
        let url = contextTargetURL() ?? selectedURLs().first ?? currentURL
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
        let isDir = values?.isDirectory == true
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        let mod: String
        if let date = values?.contentModificationDate {
            mod = formatter.string(from: date)
        } else {
            mod = "--"
        }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = url.lastPathComponent
        alert.addButton(withTitle: "OK")

        if isDir {
            alert.informativeText = """
            Ruta: \(url.path)
            Tipo: Carpeta
            Tamano logico: calculando...
            Tamano en disco: calculando...
            Elementos: calculando...
            Carpetas: calculando... | Archivos: calculando...
            Modificado: \(mod)
            """
            presentInfoAlert(alert)

            DispatchQueue.global(qos: .userInitiated).async { [weak alert] in
                let stats = self.directoryStats(for: url)
                let logicalSize = ByteCountFormatter.string(fromByteCount: stats.logicalBytes, countStyle: .file)
                let allocatedSize = ByteCountFormatter.string(fromByteCount: stats.allocatedBytes, countStyle: .file)
                let text = """
                Ruta: \(url.path)
                Tipo: Carpeta
                Tamano logico: \(logicalSize)
                Tamano en disco: \(allocatedSize)
                Elementos: \(stats.fileCount + stats.directoryCount)
                Carpetas: \(stats.directoryCount) | Archivos: \(stats.fileCount)
                Modificado: \(mod)
                """
                DispatchQueue.main.async {
                    guard let alert else { return }
                    alert.informativeText = text
                }
            }
            return
        }

        let size = ByteCountFormatter.string(fromByteCount: Int64(values?.fileSize ?? 0), countStyle: .file)
        let allocated = ByteCountFormatter.string(
            fromByteCount: Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0),
            countStyle: .file
        )
        alert.informativeText = """
        Ruta: \(url.path)
        Tipo: Archivo
        Tamano logico: \(size)
        Tamano en disco: \(allocated)
        Elementos: --
        Carpetas: -- | Archivos: --
        Modificado: \(mod)
        """
        presentInfoAlert(alert)
    }

    func showInfoForCurrentDirectory() {
        let originalSelection = tableView.selectedRowIndexes
        tableView.deselectAll(nil)
        rootSelected = true
        contextShowInfo()
        rootSelected = false
        if !originalSelection.isEmpty {
            tableView.selectRowIndexes(originalSelection, byExtendingSelection: false)
        }
    }

    private func presentInfoAlert(_ alert: NSAlert) {
        if let window = view.window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private func directoryStats(for root: URL) -> (logicalBytes: Int64, allocatedBytes: Int64, fileCount: Int, directoryCount: Int) {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .isDirectoryKey,
            .fileSizeKey,
            .fileAllocatedSizeKey,
            .totalFileAllocatedSizeKey,
            .fileResourceIdentifierKey
        ]
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: []
        ) else {
            return (0, 0, 0, 0)
        }

        var logicalBytes: Int64 = 0
        var allocatedBytes: Int64 = 0
        var fileCount = 0
        var directoryCount = 0
        var seenResourceIDs = Set<String>()

        for case let child as URL in enumerator {
            guard let childValues = try? child.resourceValues(forKeys: Set(keys)) else { continue }
            if childValues.isDirectory == true {
                directoryCount += 1
                continue
            }
            if childValues.isRegularFile == true {
                if let rid = childValues.fileResourceIdentifier {
                    let key = String(describing: rid)
                    if seenResourceIDs.contains(key) {
                        continue
                    }
                    seenResourceIDs.insert(key)
                }
                fileCount += 1
                logicalBytes += Int64(childValues.fileSize ?? 0)
                allocatedBytes += Int64(childValues.totalFileAllocatedSize ?? childValues.fileAllocatedSize ?? childValues.fileSize ?? 0)
            }
        }

        return (logicalBytes, allocatedBytes, fileCount, directoryCount)
    }

    @objc private func contextRename() {
        guard let source = contextTargetURL() else {
            onStatus?("Selecciona un unico elemento para renombrar.")
            return
        }
        let clean = promptForText(title: "Renombrar", message: "Nuevo nombre para '\(source.lastPathComponent)'.", defaultValue: source.lastPathComponent)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !clean.isEmpty else { return }

        do {
            try renameItem(at: source, to: clean)
            onStatus?("Renombrado: \(source.lastPathComponent) -> \(clean)")
        } catch {
            onStatus?("No se pudo renombrar: \(error.localizedDescription)")
            NSSound.beep()
        }
    }

    @objc private func contextDeleteToTrash() {
        let count = deleteSelectedToTrash()
        onStatus?("Enviados a Papelera: \(count)")
    }

    @objc private func contextDeletePermanent() {
        let selected = selectedURLs()
        guard !selected.isEmpty else { return }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Eliminar definitivamente \(selected.count) elemento(s)"
        alert.informativeText = "Esta accion no se puede deshacer."
        alert.addButton(withTitle: "Eliminar")
        alert.addButton(withTitle: "Cancelar")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let count = deleteSelectedPermanently()
        onStatus?("Eliminados definitivamente: \(count)")
    }

    private func createDirectoryWithIncrementalName(baseName: String) throws -> URL {
        let fm = FileManager.default
        var index = 0
        while true {
            let candidateName = index == 0 ? baseName : "\(baseName) \(index + 1)"
            let candidate = currentDirectoryURL.appendingPathComponent(candidateName, isDirectory: true)
            if !fm.fileExists(atPath: candidate.path) {
                try fm.createDirectory(at: candidate, withIntermediateDirectories: false)
                refreshCurrentDirectory()
                return candidate
            }
            index += 1
        }
    }

    private func contextTargetURL() -> URL? {
        let clicked = tableView.clickedRow
        if clicked >= 0, clicked < rows.count {
            return rows[clicked].url
        }

        let mousePointInTable = tableView.convert(NSEvent.mouseLocation, from: nil)
        let rowAtMouse = tableView.row(at: mousePointInTable)
        if rowAtMouse >= 0, rowAtMouse < rows.count {
            return rows[rowAtMouse].url
        }

        let selected = selectedURLs()
        guard selected.count == 1 else { return nil }
        return selected[0]
    }

    private func promptForText(title: String, message: String, defaultValue: String) -> String? {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Aceptar")
        alert.addButton(withTitle: "Cancelar")

        let input = NSTextField(string: defaultValue)
        input.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        alert.accessoryView = input
        let alertWindow = alert.window
        alertWindow.initialFirstResponder = input
        _ = alertWindow.makeFirstResponder(input)
        input.selectText(nil)

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }
        return input.stringValue
    }

    private func availableDestination(for proposed: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: proposed.path) else { return proposed }
        let base = proposed.deletingPathExtension().lastPathComponent
        let ext = proposed.pathExtension
        var idx = 1
        while true {
            let name = ext.isEmpty ? "\(base)-\(idx)" : "\(base)-\(idx).\(ext)"
            let candidate = proposed.deletingLastPathComponent().appendingPathComponent(name)
            if !fm.fileExists(atPath: candidate.path) {
                return candidate
            }
            idx += 1
        }
    }

    @objc private func tabSelectionChanged() {
        let idx = tabsControl.selectedSegment
        guard idx >= 0, idx < tabURLs.count, idx != activeTabIndex else { return }
        activeTabIndex = idx
        historyBack.removeAll()
        historyForward.removeAll()
        loadDirectory(tabURLs[idx], pushHistory: false)
    }

    private func refreshTabsControl() {
        tabsControl.segmentCount = tabURLs.count
        for idx in 0..<tabURLs.count {
            let url = tabURLs[idx]
            let base = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
            let title = "\(idx + 1): \(base)"
            tabsControl.setLabel(title, forSegment: idx)
            tabsControl.setWidth(120, forSegment: idx)
        }
        tabsControl.selectedSegment = activeTabIndex
    }
}

private protocol FocusAwareTableViewDelegate: AnyObject {
    func activatePanel()
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

private final class FocusAwareTableView: NSTableView {
    weak var focusDelegate: FocusAwareTableViewDelegate?
    var onEnterPressed: (() -> Void)?
    var onBackgroundClicked: (() -> Void)?

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            focusDelegate?.activatePanel()
        }
        return accepted
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 {
            onEnterPressed?()
            return
        }
        super.keyDown(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let clickedRow = row(at: point)
        super.mouseDown(with: event)
        if clickedRow < 0 {
            onBackgroundClicked?()
        }
    }
}

extension FilePanelViewController: FocusAwareTableViewDelegate {}
