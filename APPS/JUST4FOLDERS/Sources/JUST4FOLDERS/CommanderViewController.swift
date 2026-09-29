import AppKit
import Foundation
import J4FFileSystem
import J4FOps
import J4FUI
import J4ICore
import QuickLookUI
import QuickLookThumbnailing
import UniformTypeIdentifiers
import os

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
    /// v1.2 — tamaño calculado en background para carpetas (nil = aún no calculado).
    var folderSizeBytes: Int64? = nil

    var sizeDisplay: String {
        if let sizeBytes {
            return ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
        }
        if let folderSizeBytes {
            return ByteCountFormatter.string(fromByteCount: folderSizeBytes, countStyle: .file)
        }
        return "--"
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
    weak var parent: DirectoryTreeNode?
    let isParentShortcut: Bool
    var children: [DirectoryTreeNode] = []
    var isLoaded = false

    init(url: URL, parent: DirectoryTreeNode? = nil, isParentShortcut: Bool = false) {
        self.url = url
        self.parent = parent
        self.isParentShortcut = isParentShortcut
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

/// Ola 1 — miniaturas reales (imagen/PDF/vídeo) con caché LRU y generación perezosa.
private final class FileThumbnailCache {
    private let lock = NSLock()
    private let cache = NSCache<NSString, NSImage>()
    private var inFlight: Set<String> = []
    private let size: CGFloat

    init(size: CGFloat = 40, countLimit: Int = 512) {
        self.size = size
        cache.countLimit = countLimit
    }

    func cached(for url: URL) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }
        return cache.object(forKey: url.standardizedFileURL.path as NSString)
    }

    /// Pide la miniatura si el tipo es «visual»; `completion` se llama en main al terminar.
    func request(for url: URL, completion: @escaping () -> Void) {
        let key = url.standardizedFileURL.path
        lock.lock()
        if cache.object(forKey: key as NSString) != nil || inFlight.contains(key) {
            lock.unlock()
            return
        }
        guard Self.isEligible(url) else {
            lock.unlock()
            return
        }
        inFlight.insert(key)
        lock.unlock()

        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: size, height: size),
            scale: 2,
            representationTypes: .thumbnail
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
            guard let self else { return }
            self.lock.lock()
            if let image = representation?.nsImage {
                self.cache.setObject(image, forKey: key as NSString)
            }
            self.inFlight.remove(key)
            self.lock.unlock()
            if representation != nil {
                DispatchQueue.main.async { completion() }
            }
        }
    }

    private static func isEligible(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image) || type.conforms(to: .pdf) || type.conforms(to: .movie)
    }
}

private let sharedThumbnailCache = FileThumbnailCache(size: 40, countLimit: 512)
/// Ola 3 — miniaturas grandes para la galería.
private let sharedGalleryThumbnailCache = FileThumbnailCache(size: 256, countLimit: 256)

/// Ola 3 — árbol de carpetas por panel (perezoso, solo carpetas, sin ocultos).
private final class PanelTreeController: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
    weak var panel: FilePanelViewController?
    weak var outlineView: NSOutlineView?

    private let root: URL
    private var childrenCache: [String: [URL]] = [:]

    init(root: URL) {
        self.root = root
        super.init()
    }

    private func children(of url: URL) -> [URL] {
        let key = url.standardizedFileURL.path
        if let cached = childrenCache[key] { return cached }
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let dirs = entries.filter { candidate in
            (try? candidate.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                && !candidate.lastPathComponent.hasSuffix(".app")
        }.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
        childrenCache[key] = dirs
        return dirs
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil { return 1 }
        guard let url = item as? URL else { return 0 }
        return children(of: url).count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil { return root }
        guard let url = item as? URL else { return root }
        return children(of: url)[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let url = item as? URL else { return false }
        return !children(of: url).isEmpty
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let url = item as? URL else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("PanelTreeCell")
        let cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = identifier
        let label: NSTextField
        if let existing = cell.textField {
            label = existing
        } else {
            label = NSTextField(labelWithString: "")
            label.translatesAutoresizingMaskIntoConstraints = false
            label.lineBreakMode = .byTruncatingMiddle
            label.font = .systemFont(ofSize: 11)
            cell.textField = label
            cell.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }
        label.stringValue = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        return cell
    }

    @objc func treeDoubleClicked(_ sender: Any?) {
        guard let outlineView, outlineView.clickedRow >= 0,
              let url = outlineView.item(atRow: outlineView.clickedRow) as? URL else { return }
        panel?.openPath(url.path)
    }
}

/// Ola 3 — celda de la galería (miniatura + nombre).
private final class GalleryItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("GalleryItem")

    private let thumb = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 8

        thumb.imageScaling = .scaleProportionallyUpOrDown
        thumb.wantsLayer = true
        thumb.layer?.cornerRadius = 6
        thumb.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.10).cgColor
        nameLabel.font = .systemFont(ofSize: 10)
        nameLabel.alignment = .center
        nameLabel.lineBreakMode = .byTruncatingMiddle

        for subview in [thumb, nameLabel] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(subview)
        }
        // v2.0 — el tamaño lo fija itemSize: la miniatura se estira para llenar la celda.
        NSLayoutConstraint.activate([
            thumb.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            thumb.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
            thumb.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6),
            nameLabel.topAnchor.constraint(equalTo: thumb.bottomAnchor, constant: 4),
            nameLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            nameLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
            container.bottomAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2)
        ])
        view = container
    }

    override var isSelected: Bool {
        didSet { updateSelectionAppearance() }
    }

    func configure(with row: FileRow) {
        nameLabel.stringValue = row.name
        if row.isDirectory {
            thumb.image = sharedFileIconCache.icon(for: row)
        } else if let cached = sharedGalleryThumbnailCache.cached(for: row.url) {
            thumb.image = cached
        } else {
            thumb.image = sharedFileIconCache.icon(for: row)
            sharedGalleryThumbnailCache.request(for: row.url) { [weak self] in
                guard let self, let image = sharedGalleryThumbnailCache.cached(for: row.url) else { return }
                self.thumb.image = image
            }
        }
        updateSelectionAppearance()
    }

    private func updateSelectionAppearance() {
        view.layer?.backgroundColor = isSelected
            ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.35).cgColor
            : nil
    }
}

/// Ola 3 — fila con hover sutil (no se dibuja sobre la seleccionada).
private final class HoverRowView: NSTableRowView {
    var hovered = false {
        didSet { if hovered != oldValue { needsDisplay = true } }
    }

    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)
        guard hovered, !isSelected else { return }
        NSColor.selectedContentBackgroundColor.withAlphaComponent(0.10).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 1), xRadius: 4, yRadius: 4).fill()
    }
}

final class CommanderViewController: NSViewController, NSToolbarDelegate, NSSearchFieldDelegate, NSControlTextEditingDelegate, NSTableViewDataSource, NSTableViewDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate, NSToolbarItemValidation, QLPreviewPanelDataSource, QLPreviewPanelDelegate, NSMenuDelegate {
    private enum ToolbarID {
        static let root = NSToolbar.Identifier("j4f.toolbar.main")
        static let back = NSToolbarItem.Identifier("j4f.toolbar.back")
        static let forward = NSToolbarItem.Identifier("j4f.toolbar.forward")
        static let home = NSToolbarItem.Identifier("j4f.toolbar.home")
        /// v2.2b — alterna 2 paneles ⇄ 1 panel (botón de la barra de herramientas).
        static let panelMode = NSToolbarItem.Identifier("j4f.toolbar.panelMode")
        static let newTab = NSToolbarItem.Identifier("j4f.toolbar.newTab")
        static let copy = NSToolbarItem.Identifier("j4f.toolbar.copy")
        static let move = NSToolbarItem.Identifier("j4f.toolbar.move")
        static let delete = NSToolbarItem.Identifier("j4f.toolbar.delete")
        static let mkdir = NSToolbarItem.Identifier("j4f.toolbar.mkdir")
        static let rename = NSToolbarItem.Identifier("j4f.toolbar.rename")
        static let deletePermanent = NSToolbarItem.Identifier("j4f.toolbar.deletePermanent")
        static let tasks = NSToolbarItem.Identifier("j4f.toolbar.tasks")
        static let refresh = NSToolbarItem.Identifier("j4f.toolbar.refresh")
        static let search = NSToolbarItem.Identifier("j4f.toolbar.search")
        /// v2.3.6 — indicadores de CPU/RAM/batería al final de la barra.
        static let monitor = NSToolbarItem.Identifier("j4f.toolbar.monitor")
    }

    private let leftPanel = FilePanelViewController(side: .left)
    private let rightPanel = FilePanelViewController(side: .right)
    private let bookmarkStore = SecurityScopedBookmarkStore()
    private let favoriteStore = FavoriteLocationStore()
    private let recentStore = RecentLocationStore()
    private let indexedSearch = IndexedSearchService.shared
    private let jobQueue = JobQueueService()
    private let leftWatcher = DirectoryWatchService()
    private let rightWatcher = DirectoryWatchService()
    private let diagnosticsExporter = DiagnosticsExporter()
    private var taskManagerWindow: TaskManagerWindowController?
    /// v1.2 — ventana de renombrado en lote (se libera al terminar o cerrar).
    private var batchRenameWindow: BatchRenameWindowController?
    /// v1.2 — ventana de duplicados (una a la vez).
    private var duplicatesWindow: DuplicatesWindowController?
    /// v2.0 — ventana de «Ordenar esta carpeta» (una a la vez).
    private var orderingWindow: OrderingWindowController?
    /// Ola 3 — paleta de comandos (⌘K).
    private var commandPalette: CommandPaletteWindowController?
    private var shortcutEditor: ShortcutEditorWindowController?
    /// Ola 1 — panel que alimenta el QuickLook (Espacio).
    private weak var previewPanelSource: FilePanelViewController?
    /// Ola 2 — vista previa lateral (⌥⌘P) y progreso de trabajos en la ventana.
    private let previewPane = NSView()
    private var previewView: QLPreviewView?
    private let previewInfoLabel = NSTextField(labelWithString: "")
    /// v2.1 — icono del estado vacío del preview (sin selección).
    private let previewPlaceholderIcon = NSImageView()
    /// v2.3 (Panel Hub F1) — selector de módulo del panel derecho y host del contenido.
    private let previewModuleSelector = NSSegmentedControl(
        labels: ["Vista previa", "DESK", "PICT"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let previewContentHost = NSView()
    private let pictMiniPanel = PictMiniPanelView()
    private let deskMiniPanel = DeskMiniPanelView(
        inboxURL: FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Downloads", isDirectory: true)
    )
    private var previewModule = UserDefaults.standard.string(forKey: "j4f.previewModule") ?? "preview"

    // v2.1 — barra lateral de navegación: árbol colapsable + sección de reautorización dinámica.
    private var sidebarTreeExpanded = (UserDefaults.standard.object(forKey: "j4f.sidebarTreeExpanded") as? Bool) ?? false
    private var sidebarTreeScroll: NSScrollView?
    private var sidebarTreeHeightConstraint: NSLayoutConstraint?
    private var sidebarReauthLabel: NSTextField?
    private var sidebarReauthScroll: NSScrollView?
    private let treeSidebarDisclosureButton = NSButton()
    private var previewPaneVisible = UserDefaults.standard.bool(forKey: "j4f.previewPaneVisible")
    private let jobProgressBar = NSProgressIndicator()
    private let jobProgressLabel = NSTextField(labelWithString: "")
    /// Ola 2 — menús del historial (clic derecho en atrás/adelante).
    private let backHistoryMenu = NSMenu()
    private let forwardHistoryMenu = NSMenu()

    private var activeSide: PanelSide = .left {
        didSet {
            updateActiveIndicator()
            updatePreviewPane()
            // v2.2 — en modo de un solo panel, alternar el activo cambia el panel visible.
            if singlePanelMode {
                applyPanelMode()
            }
        }
    }

    /// v2.2 — modo de un solo panel: solo se muestra el panel activo (Tab alterna cuál se ve).
    private var singlePanelMode = false
    static let singlePanelModeKey = "j4f.singlePanelMode"
    /// v2.2b — botón de la barra de herramientas que alterna 2 paneles ⇄ 1 panel.
    private weak var panelModeToolbarItem: NSToolbarItem?
    private weak var panelModeToolbarButton: NSButton?
    /// v2.3.6 — indicadores de CPU/RAM/batería al final del toolbar (vista creada una vez).
    private lazy var systemMonitorView = SystemMonitorView()

    private let activeIndicatorLabel = NSTextField(labelWithString: "IZQ")
    /// v2.1 — split raíz (autocuración de divisorias).
    private weak var bodySplit: NSSplitView?
    private weak var bottomStackView: NSStackView?
    private var bottomStackHeight: NSLayoutConstraint?
    /// v2.1 — split de paneles (autocuración del reparto 50/50).
    private weak var panelsSplit: NSSplitView?
    private let statusLabel = NSTextField(labelWithString: "Listo")
    private let volumeWarningLabel = NSTextField(labelWithString: "")
    private let searchField = NSSearchField()
    /// v2.0 — registro propio del commander (os_log; visible con `log stream`).
    private let logger = Logger(subsystem: "com.dmx83.just4folders", category: "commander")
    /// v2.0 — scope de búsqueda del campo (⌘F): false = carpeta actual; true = todo el índice.
    private var globalSearchScope = false
    /// v2.0 — throttle del estado de progreso de indexado (evita repintar por lote).
    private var lastIndexProgressUpdate: Date = .distantPast
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
    private var isUpdatingDirectoryTreeSelection = false
    private lazy var homeDirectoryURL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).standardizedFileURL
    private var expandedTreePathsBySide: [PanelSide: Set<String>] = [.left: [], .right: []]
    private var selectedTreePathBySide: [PanelSide: String] = [:]
    // v2.1.1 — pista cuando no hay ubicaciones autorizadas + menús de la barra lateral.
    private var sidebarLocationsEmptyHint: NSTextField?
    private weak var authorizedSidebarMenu: NSMenu?
    private weak var favoritesSidebarMenu: NSMenu?
    private weak var recentsSidebarMenu: NSMenu?
    private weak var reauthSidebarMenu: NSMenu?
    private var cooperativeIndexTask: Task<Void, Never>?
    private var cooperativeIndexDebounceWorkItem: DispatchWorkItem?
    private var isCooperativeIndexing = false

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
        refreshToolbarValidation()
        syncDirectoryTreeToActivePanel()
        scheduleCooperativeIndexing()
        NotificationCenter.default.addObserver(self, selector: #selector(focusPathBar), name: .j4fFocusPathBar, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onPreferencesChanged), name: .j4fPreferencesChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onToggleFlatViewRequested), name: .j4fToggleFlatView, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onBatchRenameRequested), name: .j4fBatchRename, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onFindDuplicatesRequested), name: .j4fFindDuplicates, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onOrderFolderRequested), name: .j4fOrderFolder, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onUndoOrderingRequested), name: .j4fUndoOrdering, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onTogglePreviewRequested), name: .j4fTogglePreview, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onToggleSinglePanelRequested), name: .j4fToggleSinglePanel, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onDuplicateTabRequested), name: .j4fDuplicateTab, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onRenameTabRequested), name: .j4fRenameTab, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onMoveTabLeftRequested), name: .j4fMoveTabLeft, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onMoveTabRightRequested), name: .j4fMoveTabRight, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onOpenCommandPaletteRequested), name: .j4fCommandPalette, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onWorkspaceSaveRequested), name: .j4fWorkspaceSave, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onRestoreLastWorkspaceRequested), name: .j4fWorkspaceRestoreLast, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onWorkspaceRestoreRequested(_:)), name: .j4fWorkspaceRestore, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onToggleGalleryRequested), name: .j4fToggleGallery, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onTogglePanelTreeRequested), name: .j4fTogglePanelTree, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onGalleryThumbSizeRequested(_:)), name: .j4fGalleryThumbSize, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onToggleSemanticSearchRequested), name: .j4fToggleSemanticSearch, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onEditShortcutsRequested), name: .j4fEditShortcuts, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onExportDiagnosticsRequested), name: .j4fExportDiagnostics, object: nil)
    }

    /// Ola 3 — alterna lista/galería del panel activo (⌥⌘G).
    @objc private func onToggleGalleryRequested() {
        activePanel.setGalleryMode(!activePanel.isGalleryMode)
    }

    /// Ola 3 — muestra/oculta el árbol de carpetas del panel activo (⌥⌘E).
    @objc private func onTogglePanelTreeRequested() {
        activePanel.setPanelTreeVisible(!activePanel.isPanelTreeVisible)
    }

    /// v2.0 — tamaño de miniaturas de la galería en ambos paneles (S/M/L).
    @objc private func onGalleryThumbSizeRequested(_ note: Notification) {
        guard let key = note.userInfo?["size"] as? String else { return }
        leftPanel.setGalleryThumbSize(key)
        rightPanel.setGalleryThumbSize(key)
        statusLabel.stringValue = "Miniaturas de la galería: tamaño \(key)."
    }

    /// v2.0 — activa/desactiva la búsqueda semántica con IA (⌥⌘B).
    @objc private func onToggleSemanticSearchRequested() {
        let enabling = !UserDefaults.standard.bool(forKey: "j4f.semanticSearch")
        leftPanel.setSemanticSearch(enabling)
        rightPanel.setSemanticSearch(enabling)
        if enabling && !leftPanel.isSemanticSearchAvailable {
            statusLabel.stringValue = "Búsqueda semántica activada, pero sin clave de IA (DEEPSEEK_API_KEY o .env.secrets): de momento busca de forma literal."
        } else {
            statusLabel.stringValue = enabling
                ? "Búsqueda semántica activada: la IA interpretará tus consultas."
                : "Búsqueda semántica desactivada."
        }
    }

    /// v2.0 — editor de atajos configurables (⌥⌘K).
    @objc private func onEditShortcutsRequested() {
        if shortcutEditor == nil {
            shortcutEditor = ShortcutEditorWindowController()
        }
        shortcutEditor?.window?.center()
        shortcutEditor?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// v2.3.6 — exportar diagnóstico desde el menú Operaciones (antes era botón del toolbar).
    @objc private func onExportDiagnosticsRequested() {
        exportDiagnostics()
    }

    // MARK: - Paleta de comandos (Ola 3)

    @objc private func onOpenCommandPaletteRequested() {
        openCommandPalette()
    }

    func openCommandPalette() {
        commandPalette?.close()
        let commands: [CommandPaletteWindowController.Command] = [
            .init(title: "Nueva carpeta", hint: "F7") { [weak self] in self?.createDirectory() },
            .init(title: "Nueva pestaña", hint: "⌘T") { [weak self] in self?.newTab() },
            .init(title: "Duplicar pestaña", hint: "⌥⌘T") { [weak self] in self?.onDuplicateTabRequested() },
            .init(title: "Renombrar pestaña…", hint: "⌥⌘R") { [weak self] in self?.onRenameTabRequested() },
            .init(title: "Cerrar pestaña", hint: "⌘W") { [weak self] in self?.closeTabOrWindow() },
            .init(title: "Ir a ruta…", hint: "⌘L") { NotificationCenter.default.post(name: .j4fFocusPathBar, object: nil) },
            .init(title: "Ir al Home", hint: "") { [weak self] in self?.goHome() },
            .init(title: "Buscar en todo el índice", hint: "⌘F") { [weak self] in self?.setGlobalSearchScope(true, announce: true) },
            .init(title: "Buscar solo en esta carpeta", hint: "") { [weak self] in self?.setGlobalSearchScope(false, announce: true) },
            .init(title: "Atrás", hint: "") { [weak self] in self?.goBack() },
            .init(title: "Adelante", hint: "") { [weak self] in self?.goForward() },
            .init(title: "Copiar al otro panel", hint: "F5") { [weak self] in self?.copySelection() },
            .init(title: "Mover al otro panel", hint: "F6") { [weak self] in self?.moveSelection() },
            .init(title: "Renombrar elemento", hint: "F2") { [weak self] in self?.renameSelection() },
            .init(title: "Enviar a la Papelera", hint: "F8") { [weak self] in self?.deleteSelection() },
            .init(title: "QuickLook (vista rápida)", hint: "Espacio · F3") { [weak self] in _ = self?.toggleQuickLookPreview() },
            .init(title: "Vista aplanada", hint: "⌥⌘F") { [weak self] in self?.onToggleFlatViewRequested() },
            .init(title: "Vista previa lateral", hint: "⌥⌘P") { [weak self] in self?.onTogglePreviewRequested() },
            .init(title: singlePanelMode ? "Usar dos paneles" : "Usar un solo panel", hint: "⌘\\") { [weak self] in self?.toggleSinglePanelMode() },
            .init(title: "Vista en galería / lista", hint: "⌥⌘G") { [weak self] in self?.onToggleGalleryRequested() },
            .init(title: "Árbol en el panel", hint: "⌥⌘E") { [weak self] in self?.onTogglePanelTreeRequested() },
            .init(title: "Tamaño de miniaturas: cíclico S→M→L", hint: "") {
                let order = ["S", "M", "L"]
                let current = UserDefaults.standard.string(forKey: "j4f.galleryThumbSize") ?? "M"
                let next = order[(order.firstIndex(of: current).map { $0 + 1 } ?? 0) % order.count]
                NotificationCenter.default.post(name: .j4fGalleryThumbSize, object: nil, userInfo: ["size": next])
            },
            .init(title: "Búsqueda semántica (IA) — activar/desactivar", hint: "⌥⌘B") { [weak self] in self?.onToggleSemanticSearchRequested() },
            .init(title: "Editar atajos…", hint: "⌥⌘K") { [weak self] in self?.onEditShortcutsRequested() },
            .init(title: "Exportar diagnóstico…", hint: "") { [weak self] in self?.exportDiagnostics() },
            .init(title: "Renombrar en lote…", hint: "⇧⌘R") { [weak self] in self?.onBatchRenameRequested() },
            .init(title: "Buscar duplicados…", hint: "⇧⌘D") { [weak self] in self?.onFindDuplicatesRequested() },
            .init(title: "Ordenar esta carpeta…", hint: "⌥⌘O") { [weak self] in self?.onOrderFolderRequested() },
            .init(title: "Deshacer última ordenación", hint: "⌥⌘Z") { [weak self] in self?.onUndoOrderingRequested() },
            .init(title: "Guardar workspace…", hint: "⌥⌘S") { [weak self] in self?.onWorkspaceSaveRequested() },
            .init(title: "Restaurar último workspace", hint: "⌥⌘L") { [weak self] in self?.restoreLastWorkspace() },
            .init(title: "Seleccionar todo", hint: "⌘A") { [weak self] in self?.activePanel.selectAllItems() }
        ]
        let controller = CommandPaletteWindowController(commands: commands)
        controller.onClose = { [weak self] in self?.commandPalette = nil }
        commandPalette = controller
        controller.present()
    }

    // MARK: - Modo de un solo panel (v2.2)

    /// v2.2 — alterna Commander (dos paneles) ⇄ panel único. Persistente; Tab cambia cuál se ve.
    func toggleSinglePanelMode() {
        singlePanelMode.toggle()
        UserDefaults.standard.set(singlePanelMode, forKey: Self.singlePanelModeKey)
        applyPanelMode()
        updatePanelModeToolbarItem()
        statusLabel.stringValue = singlePanelMode
            ? "Modo de un solo panel — Tab alterna entre izquierdo y derecho."
            : "Modo commander: dos paneles."
    }

    /// v2.2b — el icono del botón muestra el reparto actual y el tooltip la acción
    /// (mismo criterio que el ítem del menú Navegación y la paleta).
    private var panelModeSymbolName: String {
        singlePanelMode ? "rectangle" : "rectangle.split.2x1"
    }

    private var panelModeTooltip: String {
        singlePanelMode ? "Usar dos paneles (⌘\\)" : "Usar un solo panel (⌘\\)"
    }

    /// v2.2b — refresca el botón tras cualquier cambio de modo (⌘\\, menú Navegación, paleta o
    /// el propio botón).
    private func updatePanelModeToolbarItem() {
        panelModeToolbarButton?.image = NSImage(
            systemSymbolName: panelModeSymbolName,
            accessibilityDescription: "Alternar uno o dos paneles"
        )
        panelModeToolbarButton?.toolTip = panelModeTooltip
        panelModeToolbarItem?.label = singlePanelMode ? "Usar dos paneles" : "Usar un solo panel"
        panelModeToolbarItem?.toolTip = panelModeTooltip
    }

    /// v2.2 — muestra solo el panel activo. En modo simple se desactiva el reparto manual del
    /// split (J4FPanelSplitView) para que el panel oculto colapse y el visible ocupe el ancho.
    private func applyPanelMode() {
        let hideLeft = singlePanelMode && activeSide == .right
        let hideRight = singlePanelMode && activeSide == .left
        leftPanel.view.isHidden = hideLeft
        rightPanel.view.isHidden = hideRight
        (panelsSplit as? J4FPanelSplitView)?.setManualWidthsEnabled(!singlePanelMode)
        if !singlePanelMode {
            healSplitLayoutIfNeeded()
        }
        // v2.2 — el viewport cambia drásticamente: reajuste completo en el siguiente ciclo
        // (cuando el split ya tiene el ancho definitivo), no con el ancho transitorio.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.leftPanel.invalidateColumnFit()
            self.rightPanel.invalidateColumnFit()
        }
    }

    @objc private func onToggleSinglePanelRequested() {
        toggleSinglePanelMode()
    }

    // MARK: - Workspaces (Ola 3)

    @objc private func onWorkspaceSaveRequested() {
        let alert = NSAlert()
        alert.messageText = "Guardar workspace"
        alert.informativeText = "Guarda pestañas, pestaña activa y vista previa de ambos paneles."
        alert.addButton(withTitle: "Guardar")
        alert.addButton(withTitle: "Cancelar")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.placeholderString = "Nombre del workspace"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        saveWorkspace(named: field.stringValue)
    }

    private func saveWorkspace(named name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            statusLabel.stringValue = "Nombre de workspace vacío."
            NSSound.beep()
            return
        }
        let workspace = Workspace(
            name: clean,
            left: leftPanel.workspaceSnapshot(),
            right: rightPanel.workspaceSnapshot(),
            previewPaneVisible: previewPaneVisible
        )
        WorkspaceStore.shared.save(workspace)
        UserDefaults.standard.set(clean, forKey: "j4f.lastWorkspace")
        statusLabel.stringValue = "Workspace «\(clean)» guardado."
    }

    @objc private func onWorkspaceRestoreRequested(_ notification: Notification) {
        guard let name = notification.userInfo?["name"] as? String else { return }
        restoreWorkspace(named: name)
    }

    @objc private func onRestoreLastWorkspaceRequested() {
        restoreLastWorkspace()
    }

    private func restoreLastWorkspace() {
        guard let name = UserDefaults.standard.string(forKey: "j4f.lastWorkspace"),
              WorkspaceStore.shared.workspace(named: name) != nil else {
            statusLabel.stringValue = "No hay ningún workspace guardado."
            NSSound.beep()
            return
        }
        restoreWorkspace(named: name)
    }

    private func restoreWorkspace(named name: String) {
        guard let workspace = WorkspaceStore.shared.workspace(named: name) else { return }
        leftPanel.restoreWorkspace(workspace.left)
        rightPanel.restoreWorkspace(workspace.right)
        previewPaneVisible = workspace.previewPaneVisible
        previewPane.isHidden = !previewPaneVisible
        UserDefaults.standard.set(previewPaneVisible, forKey: "j4f.previewPaneVisible")
        UserDefaults.standard.set(name, forKey: "j4f.lastWorkspace")
        updatePreviewPane()
        statusLabel.stringValue = "Workspace «\(name)» restaurado."
    }

    /// Ola 2 — vista previa lateral (menu Navegación, ⌥⌘P).
    @objc private func onTogglePreviewRequested() {
        togglePreviewPane()
    }

    // MARK: - Pestañas (Ola 2)

    @objc private func onDuplicateTabRequested() {
        activePanel.duplicateCurrentTab()
        statusLabel.stringValue = "Pestaña duplicada (panel \(activeSide.rawValue))."
    }

    @objc private func onRenameTabRequested() {
        // v2.3.6 — el diálogo vive en el panel: lo comparten ⌥⌘R y el clic derecho sobre una tab.
        activePanel.promptRenameActiveTab()
    }

    @objc private func onMoveTabLeftRequested() {
        activePanel.moveCurrentTab(by: -1)
    }

    @objc private func onMoveTabRightRequested() {
        activePanel.moveCurrentTab(by: 1)
    }

    /// v1.2 — renombrado en lote del panel activo (menú Operaciones ⇧⌘R o menú contextual).
    @objc private func onBatchRenameRequested() {
        let urls = activePanel.selectedURLs()
        guard !urls.isEmpty else {
            statusLabel.stringValue = "Selecciona al menos un elemento para renombrar en lote."
            NSSound.beep()
            return
        }
        let controller = BatchRenameWindowController(urls: urls) { [weak self] renamed in
            guard let self else { return }
            self.statusLabel.stringValue = "Renombrados \(renamed) elemento(s) en lote."
            self.activePanel.reloadAfterExternalChange()
            self.batchRenameWindow = nil
        }
        batchRenameWindow = controller
        controller.window?.center()
        controller.showWindow(nil)
    }

    /// v1.2 — duplicados bajo la carpeta del panel activo (menú Operaciones ⇧⌘D).
    @objc private func onFindDuplicatesRequested() {
        openDuplicates(for: activePanel.currentDirectoryURL)
    }

    /// v1.2 — abre la ventana de duplicados para el subárbol de `root`.
    func openDuplicates(for root: URL) {
        duplicatesWindow?.close()
        let controller = DuplicatesWindowController(root: root) { [weak self] in
            guard let self else { return }
            self.duplicatesWindow = nil
            self.activePanel.reloadAfterExternalChange()
        }
        duplicatesWindow = controller
        controller.window?.center()
        controller.showWindow(nil)
    }

    /// v2.0 — «Ordenar esta carpeta» sobre el panel activo (menú Operaciones ⌥⌘O o contextual).
    @objc private func onOrderFolderRequested() {
        openOrdering(for: activePanel.currentDirectoryURL)
    }

    /// v2.0 — abre la ventana de ordenación (clasificar + mover con diario para deshacer).
    func openOrdering(for folder: URL) {
        orderingWindow?.close()
        // v2.3.2 (F3) — destino recordado por carpeta (precarga en la ventana).
        let controller = OrderingWindowController(folder: folder, initialDestination: rememberedDestination(for: folder)) { [weak self] moved in
            guard let self else { return }
            // v2.3 (F2) — recuerda dónde quedan los «sin clasificar» del último destino.
            if let destination = self.orderingWindow?.currentDestination {
                UserDefaults.standard.set(destination.path, forKey: "j4f.lastOrderingDestination")
                self.rememberDestination(destination, for: folder)
            }
            self.orderingWindow = nil
            self.refreshDeskReview()
            self.statusLabel.stringValue = moved > 0
                ? "Ordenados \(moved) fichero(s). «Deshacer última ordenación» en el menú Operaciones."
                : "Nada que ordenar."
            self.leftPanel.reloadAfterExternalChange()
            self.rightPanel.reloadAfterExternalChange()
        }
        orderingWindow = controller
        controller.window?.center()
        controller.showWindow(nil)
    }

    /// v2.0 — deshace la última ordenación (⌥⌘Z): mueve los ficheros de vuelta a su sitio.
    @objc private func onUndoOrderingRequested() {
        let journalURL = OrderingJournalStore.defaultURL()
        let journal = OrderingJournalStore.load(from: journalURL)
        guard !journal.isEmpty else {
            statusLabel.stringValue = "No hay ninguna ordenación que deshacer."
            NSSound.beep()
            return
        }
        let result = FolderOrderer.undo(journal)
        OrderingJournalStore.clear(at: journalURL)
        var message = "Ordenación deshecha: \(result.restored) fichero(s) restaurado(s)."
        if !result.failures.isEmpty {
            message += " \(result.failures.count) fallo(s)."
        }
        statusLabel.stringValue = message
        leftPanel.reloadAfterExternalChange()
        rightPanel.reloadAfterExternalChange()
        refreshDeskReview()
    }

    /// v1.2 — alterna la vista aplanada del panel activo (menú Navegación, ⌥⌘F).
    @objc private func onToggleFlatViewRequested() {
        activePanel.setFlatView(!activePanel.flatViewActive)
        statusLabel.stringValue = activePanel.flatViewActive ? "Vista aplanada activada." : "Vista normal."
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        configureToolbarIfNeeded()
        installKeyMonitorIfNeeded()
        healSplitLayoutIfNeeded()
        // v2.1.1 — la restauración de frames del split ocurre después del primer layout;
        // un segundo intento diferido evita que el preview quede gigante al arrancar.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.healSplitLayoutIfNeeded()
        }
    }

    /// v2.2d — recalcula el alto exacto de la fila inferior según sus filas visibles
    /// (ver nota en configureLayout sobre por qué no basta con hugging/cap).
    private func refreshBottomStackHeight() {
        guard let c = bottomStackHeight, let st = bottomStackView else { return }
        let visible = st.arrangedSubviews.filter { !$0.isHidden }
        let total = visible.reduce(CGFloat(0)) { $0 + $1.fittingSize.height }
            + CGFloat(max(0, visible.count - 1)) * st.spacing
        if abs(c.constant - total) > 0.5 {
            c.constant = total
        }
    }

    /// v2.1 — autocuración del layout de la ventana: si la barra lateral o el preview quedaron
    /// con anchos inutilizables (p. ej. NSSplitView repartió a partes iguales al no haber
    /// autosave), recoloca las divisorias (250 / paneles / 220).
    /// v2.2c — solo se ejecuta al arrancar y al cambiar de modo de paneles: antes corría en cada
    /// `viewDidLayout` y revertía los arrastres del usuario (divisoria de paneles y del preview).
    private func healSplitLayoutIfNeeded() {
        guard let bodySplit, bodySplit.bounds.width > 700 else { return }
        let sidebarWidth = bodySplit.subviews.first?.frame.width ?? 0
        let previewWidth = bodySplit.subviews.last?.frame.width ?? 0
        // v2.2c — solo estados degenerados; los anchos elegidos por el usuario se respetan.
        if sidebarWidth < 160 || previewWidth < 160 {
            bodySplit.setPosition(250, ofDividerAt: 0)
            bodySplit.setPosition(bodySplit.bounds.width - 232, ofDividerAt: 1)
        }
        // Paneles: el usuario reparte libremente (p. ej. 30/70); solo se cura un reparto
        // degenerado (algún panel por debajo del mínimo usable).
        // En modo de un solo panel no aplica (uno de los dos está colapsado a propósito).
        if !singlePanelMode, let panelsSplit, panelsSplit.bounds.width > 400,
           let first = panelsSplit.subviews.first, let last = panelsSplit.subviews.last,
           first.frame.width < 120 || last.frame.width < 120 {
            panelsSplit.setPosition(panelsSplit.bounds.width / 2, ofDividerAt: 0)
        }
        // Tras cualquier ajuste, que los paneles reajusten sus columnas.
        refreshBottomStackHeight()
        leftPanel.refreshColumnLayout()
        rightPanel.refreshColumnLayout()
    }

    deinit {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        leftWatcher.stop()
        rightWatcher.stop()
        cooperativeIndexTask?.cancel()
        cooperativeIndexDebounceWorkItem?.cancel()
        stopAllScopedAccess()
        NotificationCenter.default.removeObserver(self)
    }

    private func configureLayout() {
        // v2.1.1 — la dirección vive dentro de cada panel (barra editable). La fila superior
        // se elimina: el chip del panel activo pasa junto al estado inferior.
        activeIndicatorLabel.font = J4FDesign.microFont()
        activeIndicatorLabel.textColor = J4FDesign.brand
        activeIndicatorLabel.alignment = .center
        activeIndicatorLabel.wantsLayer = true
        activeIndicatorLabel.layer?.backgroundColor = J4FDesign.brandSoft.cgColor
        activeIndicatorLabel.layer?.cornerRadius = 5
        activeIndicatorLabel.setAccessibilityLabel("Panel activo")
        activeIndicatorLabel.toolTip = "Panel activo · Tab cambia"
        activeIndicatorLabel.translatesAutoresizingMaskIntoConstraints = false
        activeIndicatorLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true
        activeIndicatorLabel.heightAnchor.constraint(equalToConstant: 18).isActive = true

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        statusLabel.setAccessibilityLabel("Estado")
        volumeWarningLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        volumeWarningLabel.textColor = .systemOrange
        volumeWarningLabel.isHidden = true
        volumeWarningLabel.setAccessibilityLabel("Advertencia de volumen")

        let panelsSplit = J4FPanelSplitView()
        panelsSplit.translatesAutoresizingMaskIntoConstraints = false
        panelsSplit.isVertical = true
        panelsSplit.dividerStyle = .thin
        // v2.2c — el reparto manual y su persistencia (j4f.panelsLeftRatio) los gestiona
        // J4FPanelSplitView: el arrastre nativo y setPosition resultaron no-op en este contexto.
        self.panelsSplit = panelsSplit

        addChild(leftPanel)
        addChild(rightPanel)
        panelsSplit.addArrangedSubview(leftPanel.view)
        panelsSplit.addArrangedSubview(rightPanel.view)
        panelsSplit.installPaneConstraints(left: leftPanel.view, right: rightPanel.view)

        let sidebarView = makeSidebarView()

        let bodySplit = J4FBodySplitView()
        bodySplit.translatesAutoresizingMaskIntoConstraints = false
        bodySplit.isVertical = true
        bodySplit.dividerStyle = .thin
        bodySplit.addArrangedSubview(sidebarView)
        bodySplit.addArrangedSubview(panelsSplit)
        sidebarView.widthAnchor.constraint(equalToConstant: 250).isActive = true
        // v2.1 — sin frames guardados NSSplitView divide a partes iguales (ignora 250/220).
        // Las prioridades hacen que al redimensionar cedan los paneles, no la barra/preview.
        bodySplit.setHoldingPriority(.defaultHigh, forSubviewAt: 0)
        bodySplit.setHoldingPriority(.defaultLow, forSubviewAt: 1)
        bodySplit.autosaveName = "j4f.split.body"
        self.bodySplit = bodySplit
        configurePreviewPane()
        bodySplit.addArrangedSubview(previewPane)
        // v2.1.1 — IMPORTANTE: la prioridad del preview debe fijarse DESPUÉS de añadirlo
        // (antes se llamaba con índice 2 inexistente y el preview se quedaba con la prioridad
        // por defecto: absorbía todo el crecimiento de la ventana y quedaba gigante).
        bodySplit.setHoldingPriority(.defaultHigh, forSubviewAt: 2)
        // v2.2d — el ancho del preview lo gestiona J4FBodySplitView (divisoria arrastrable con
        // cursor ↔ y persistencia en j4f.previewWidth); al crecer la ventana el espacio extra
        // va a los paneles.
        bodySplit.installPreviewConstraint(previewPane)

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        // Ola 2 — barra de progreso del trabajo activo (encima del estado).
        jobProgressBar.style = .bar
        jobProgressBar.isIndeterminate = false
        jobProgressBar.minValue = 0
        jobProgressBar.maxValue = 1
        jobProgressBar.controlSize = .small
        jobProgressBar.isHidden = true
        jobProgressLabel.font = .systemFont(ofSize: 11)
        jobProgressLabel.textColor = .secondaryLabelColor
        jobProgressLabel.isHidden = true
        // v2.2d — la FILA también se oculta: con los hijos ocultos pero la fila visible,
        // el stack reservaba 72pt vacíos que dejaban una banda muerta bajo los paneles.
        let jobProgressRow = NSStackView(views: [jobProgressLabel, jobProgressBar])
        jobProgressRow.orientation = .horizontal
        jobProgressRow.spacing = 8
        jobProgressRow.translatesAutoresizingMaskIntoConstraints = false
        jobProgressRow.isHidden = true
        jobProgressBar.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true

        // v2.1.1 — chip del panel activo + estado en una sola fila (sin tira superior vacía).
        let statusRow = NSStackView(views: [activeIndicatorLabel, statusLabel])
        statusRow.orientation = .horizontal
        statusRow.spacing = 8
        statusRow.alignment = .centerY
        statusRow.translatesAutoresizingMaskIntoConstraints = false

        // v2.1.1 — fila inferior compacta (avisos + progreso + estado).
        let bottomStack = NSStackView(views: [volumeWarningLabel, jobProgressRow, statusRow])
        bottomStack.orientation = .vertical
        bottomStack.spacing = 6
        bottomStack.alignment = .leading
        bottomStack.translatesAutoresizingMaskIntoConstraints = false
        // v2.2c — sin esto el stack se estiraba y se comía ~250pt del alto: los paneles
        // acababan en el aire y dejaban un hueco muerto antes de la barra de estado.
        // v2.2d — OJO: en NSStackView, setHuggingPriority(_:for:) aplica a las FILAS, no a
        // la pila; la pila necesita setContentHuggingPriority para no estirarse (se estiraba
        // a 96pt y dejaba una banda vacía de ~100pt bajo los paneles).
        bottomStack.setHuggingPriority(.required, for: .vertical)
        bottomStack.setContentHuggingPriority(.required, for: .vertical)
        // v2.2d — NSStackView no expone intrinsicContentSize, así que ni hugging ni el cap
        // gobiernan su alto (el solver le daba 96pt y dejaba una banda vacía bajo los
        // paneles). Altura EXACTA calculada de las filas visibles; refreshBottomStackHeight()
        // la recalcula cuando aparecen/desaparecen avisos o el progreso.
        bottomStackView = bottomStack
        let hConstraint = bottomStack.heightAnchor.constraint(equalToConstant: 18)
        hConstraint.priority = .required
        hConstraint.isActive = true
        bottomStackHeight = hConstraint

        container.addSubview(bodySplit)
        container.addSubview(bottomStack)
        view.addSubview(container)

        // v2.1.1 — layout directo (sin NSStackView exterior): el stack «fitting-size» ignoraba
        // los pins y el contenido quedaba centrado/encogido de forma no determinista.
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            container.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),

            bodySplit.topAnchor.constraint(equalTo: container.topAnchor),
            bodySplit.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bodySplit.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            bodySplit.bottomAnchor.constraint(equalTo: bottomStack.topAnchor, constant: -10),
            bodySplit.heightAnchor.constraint(greaterThanOrEqualToConstant: 420),

            bottomStack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bottomStack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            bottomStack.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            statusRow.widthAnchor.constraint(equalTo: bottomStack.widthAnchor),
            jobProgressRow.widthAnchor.constraint(lessThanOrEqualTo: bottomStack.widthAnchor),
            volumeWarningLabel.widthAnchor.constraint(lessThanOrEqualTo: bottomStack.widthAnchor)
        ])

        // v2.2 — modo de un solo panel (persistente): solo se ve el panel activo; Tab alterna.
        singlePanelMode = UserDefaults.standard.bool(forKey: Self.singlePanelModeKey)
        applyPanelMode()
        updatePanelModeToolbarItem()
    }

    private func makeSidebarView() -> NSView {
        let container = NSStackView()
        container.orientation = .vertical
        container.spacing = 8
        container.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        container.translatesAutoresizingMaskIntoConstraints = false
        // v2.1 — sin esto el reparto por «gravity areas» estira las tablas y deja huecos enormes.
        container.distribution = .fill
        // v2.1.1 — alignAncho real: cada fila se ancla al ancho del contenedor (la antigua
        // alignment = .width alineaba las etiquetas al borde derecho y desbordaba textos largos).
        container.alignment = .leading
        container.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        // v2.1.1 — el fondo lo pone el NSVisualEffectView (material sidebar); sin tarjeta propia.
        func addRow(_ view: NSView) {
            container.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: container.widthAnchor, constant: -16).isActive = true
        }

        directoryTree.headerView = nil
        directoryTree.selectionHighlightStyle = .sourceList
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
        // v2.2e — el árbol ABSORBE el espacio sobrante de la barra lateral (antes: altura
        // fija de 300 y el sobrante inflaba la fila «ÁRBOL», dejando un hueco enorme).
        // 249 < 250 (espaciador inferior): así el árbol se queda con todo el sobrante.
        treeScroll.setContentHuggingPriority(NSLayoutConstraint.Priority(249), for: .vertical)
        let treeHeight = treeScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 160)
        sidebarTreeScroll = treeScroll
        sidebarTreeHeightConstraint = treeHeight

        // v2.1 — barra de navegación de verdad: destinos (Ubicaciones/Favoritos/Recientes),
        // reautorización solo cuando hace falta y el árbol como sección colapsable al final.
        // Las acciones sueltas (añadir ubicación / info) viven ahora en el clic derecho.
        addRow(sidebarSectionLabel("UBICACIONES"))
        addRow(makeTableScroll(for: authorizedTable, accessibilityLabel: "Ubicaciones autorizadas"))
        // v2.1.1 — sin ubicaciones no hay ruido: una pista discreta explica cómo añadirlas.
        let locationsHint = NSTextField(labelWithString: "Sin ubicaciones. Clic derecho → «Añadir a Ubicaciones».")
        locationsHint.font = J4FDesign.captionFont()
        locationsHint.textColor = .tertiaryLabelColor
        locationsHint.lineBreakMode = .byWordWrapping
        locationsHint.maximumNumberOfLines = 2
        sidebarLocationsEmptyHint = locationsHint
        addRow(locationsHint)

        let reauthLabel = sidebarSectionLabel("REAUTORIZAR")
        let reauthScroll = makeTableScroll(for: reauthTable, accessibilityLabel: "Pendientes de reautorizar")
        sidebarReauthLabel = reauthLabel
        sidebarReauthScroll = reauthScroll
        addRow(reauthLabel)
        addRow(reauthScroll)

        addRow(sidebarSectionLabel("FAVORITOS"))
        addRow(makeTableScroll(for: favoritesTable, accessibilityLabel: "Favoritos"))

        addRow(sidebarSectionLabel("RECIENTES"))
        addRow(makeTableScroll(for: recentsTable, accessibilityLabel: "Recientes"))

        treeSidebarDisclosureButton.bezelStyle = .inline
        treeSidebarDisclosureButton.controlSize = .small
        treeSidebarDisclosureButton.target = self
        treeSidebarDisclosureButton.action = #selector(toggleSidebarTree)
        treeSidebarDisclosureButton.setAccessibilityLabel("Mostrar u ocultar el árbol")
        let treeSpacer = NSView()
        treeSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        treeSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let treeTitle = sidebarSectionLabel("ÁRBOL")
        treeTitle.setContentCompressionResistancePriority(.required, for: .horizontal)
        // v2.2e — la cabecera «ÁRBOL» va pegada a su árbol (sin estirarse con el sobrante).
        let treeHeader = NSStackView(views: [treeTitle, treeSpacer, treeSidebarDisclosureButton])
        treeHeader.orientation = .horizontal
        treeHeader.spacing = 4
        treeHeader.setContentHuggingPriority(.required, for: .vertical)
        addRow(treeHeader)
        addRow(treeScroll)

        // v2.2e — espaciador final: con el árbol colapsado no queda ninguna fila elástica
        // y el sobrante lo absorbe este espaciador (invisible) en vez de estirar cabeceras.
        let sidebarBottomSpacer = NSView()
        sidebarBottomSpacer.translatesAutoresizingMaskIntoConstraints = false
        sidebarBottomSpacer.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        addRow(sidebarBottomSpacer)

        updateReauthSectionVisibility()
        applySidebarTreeState()
        sidebarLocationsEmptyHint?.isHidden = !authorizedLocations.isEmpty

        // v2.1.1 — cada destino tiene su menú contextual (abrir, revelar, copiar, quitar).
        authorizedTable.menu = makeSidebarMenu(for: authorizedTable, removeTitle: "Quitar de Ubicaciones")
        favoritesTable.menu = makeSidebarMenu(for: favoritesTable, removeTitle: "Quitar de Favoritos")
        recentsTable.menu = makeSidebarMenu(for: recentsTable, removeTitle: "Quitar de Recientes", includeClearRecents: true)
        reauthTable.menu = makeSidebarMenu(for: reauthTable, removeTitle: nil, includeReauth: true)
        authorizedSidebarMenu = authorizedTable.menu
        favoritesSidebarMenu = favoritesTable.menu
        recentsSidebarMenu = recentsTable.menu
        reauthSidebarMenu = reauthTable.menu

        // v2.1.1 — aspecto nativo: material de barra lateral sobre la ventana (como Finder).
        let effect = NSVisualEffectView()
        effect.material = .sidebar
        effect.blendingMode = .behindWindow
        effect.state = .followsWindowActiveState
        effect.wantsLayer = true
        effect.layer?.cornerRadius = J4FDesign.Radius.medium
        effect.layer?.masksToBounds = true
        effect.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(container)
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            container.topAnchor.constraint(equalTo: effect.topAnchor),
            container.bottomAnchor.constraint(equalTo: effect.bottomAnchor)
        ])
        return effect
    }

    @objc private func toggleSidebarTree() {
        sidebarTreeExpanded.toggle()
        applySidebarTreeState()
    }

    private func applySidebarTreeState() {
        sidebarTreeScroll?.isHidden = !sidebarTreeExpanded
        sidebarTreeHeightConstraint?.isActive = sidebarTreeExpanded
        treeSidebarDisclosureButton.image = NSImage(
            systemSymbolName: sidebarTreeExpanded ? "chevron.down" : "chevron.right",
            accessibilityDescription: nil
        )
        treeSidebarDisclosureButton.toolTip = sidebarTreeExpanded ? "Ocultar el árbol" : "Mostrar el árbol de carpetas"
        UserDefaults.standard.set(sidebarTreeExpanded, forKey: "j4f.sidebarTreeExpanded")
    }

    private func updateReauthSectionVisibility() {
        let needed = !failedBookmarks.isEmpty
        sidebarReauthLabel?.isHidden = !needed
        sidebarReauthScroll?.isHidden = !needed
    }

    private func sidebarSectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = J4FDesign.microFont()
        label.textColor = .tertiaryLabelColor
        // v2.2e — las cabeceras no deben estirarse nunca: con el stack .fill, el espacio
        // sobrante las inflaba y aparecía un hueco enorme entre «ÁRBOL» y el árbol.
        label.setContentHuggingPriority(.required, for: .vertical)
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }

    private func makeTableScroll(for table: NSTableView, accessibilityLabel: String) -> NSScrollView {
        table.headerView = nil
        table.usesAlternatingRowBackgroundColors = false
        table.selectionHighlightStyle = .sourceList
        table.backgroundColor = .clear
        table.rowHeight = 24
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
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: 64).isActive = true
        scroll.setAccessibilityLabel(accessibilityLabel)
        return scroll
    }

    /// v2.1.1 — menú contextual de una sección de la barra lateral.
    private func makeSidebarMenu(
        for table: NSTableView,
        removeTitle: String?,
        includeClearRecents: Bool = false,
        includeReauth: Bool = false
    ) -> NSMenu {
        let menu = NSMenu(title: "Ubicación")

        func add(_ title: String, _ action: Selector) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = table
            menu.addItem(item)
        }

        add("Abrir en el panel activo", #selector(sidebarMenuOpen(_:)))
        add("Mostrar en Finder", #selector(sidebarMenuReveal(_:)))
        add("Copiar ruta", #selector(sidebarMenuCopyPath(_:)))
        if includeReauth {
            menu.addItem(.separator())
            add("Reautorizar…", #selector(sidebarMenuReauthorize(_:)))
        }
        if removeTitle != nil || includeClearRecents {
            menu.addItem(.separator())
        }
        if let removeTitle {
            add(removeTitle, #selector(sidebarMenuRemove(_:)))
        }
        if includeClearRecents {
            add("Limpiar recientes", #selector(sidebarMenuClearRecents(_:)))
        }
        return menu
    }

    private func sidebarClickedURL(_ table: NSTableView) -> URL? {
        let row = table.clickedRow >= 0 ? table.clickedRow : table.selectedRow
        guard row >= 0 else { return nil }
        if table == authorizedTable { return authorizedLocations[safe: row] }
        if table == favoritesTable { return favoriteLocations[safe: row] }
        if table == recentsTable { return recentLocations[safe: row] }
        if table == reauthTable, let path = failedBookmarks[safe: row]?.path, !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    @objc private func sidebarMenuOpen(_ sender: NSMenuItem) {
        guard let table = sender.representedObject as? NSTableView, let url = sidebarClickedURL(table) else { return }
        _ = beginSecurityScope(for: url)
        activePanel.openURL(url)
    }

    @objc private func sidebarMenuReveal(_ sender: NSMenuItem) {
        guard let table = sender.representedObject as? NSTableView, let url = sidebarClickedURL(table) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func sidebarMenuCopyPath(_ sender: NSMenuItem) {
        guard let table = sender.representedObject as? NSTableView, let url = sidebarClickedURL(table) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
        statusLabel.stringValue = "Ruta copiada: \(url.path)"
    }

    @objc private func sidebarMenuRemove(_ sender: NSMenuItem) {
        guard let table = sender.representedObject as? NSTableView, let url = sidebarClickedURL(table) else { return }
        if table == authorizedTable {
            bookmarkStore.remove(path: url.path)
            loadSidebarLocations()
            statusLabel.stringValue = "Ubicación quitada: \(url.lastPathComponent)"
        } else if table == favoritesTable {
            favoriteStore.remove(path: url.path)
            favoriteLocations = favoriteStore.list().map { URL(fileURLWithPath: $0) }
            favoritesTable.reloadData()
            statusLabel.stringValue = "Favorito quitado: \(url.lastPathComponent)"
        } else if table == recentsTable {
            recentStore.remove(path: url.path)
            recentLocations = recentStore.list().map { URL(fileURLWithPath: $0) }
            recentsTable.reloadData()
            statusLabel.stringValue = "Reciente quitado: \(url.lastPathComponent)"
        }
    }

    @objc private func sidebarMenuClearRecents(_ sender: NSMenuItem) {
        clearRecentLocations()
    }

    @objc private func sidebarMenuReauthorize(_ sender: NSMenuItem) {
        guard let table = sender.representedObject as? NSTableView, table == reauthTable else { return }
        let row = table.clickedRow >= 0 ? table.clickedRow : table.selectedRow
        guard row >= 0 else { return }
        reauthTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        reauthorizeSelectedBookmark()
    }

    private func configureCallbacks() {
        leftPanel.onActivate = { [weak self] in
            self?.activeSide = .left
            self?.refreshToolbarValidation()
        }
        rightPanel.onActivate = { [weak self] in
            self?.activeSide = .right
            self?.refreshToolbarValidation()
        }

        leftPanel.onStatus = { [weak self] text in
            self?.statusLabel.stringValue = "◀  \(text)"
            self?.refreshToolbarValidation()
        }
        rightPanel.onStatus = { [weak self] text in
            self?.statusLabel.stringValue = "▶  \(text)"
            self?.refreshToolbarValidation()
        }
        leftPanel.onSelectionChanged = { [weak self] in
            guard let self else { return }
            self.previewSourceSelectionChanged(self.leftPanel)
        }
        rightPanel.onSelectionChanged = { [weak self] in
            guard let self else { return }
            self.previewSourceSelectionChanged(self.rightPanel)
        }
        leftPanel.onDropRequest = { [weak self] urls, destination, copy in
            self?.enqueueFileJob(type: copy ? .copy : .move, selected: urls, destination: destination)
        }
        rightPanel.onDropRequest = { [weak self] urls, destination, copy in
            self?.enqueueFileJob(type: copy ? .copy : .move, selected: urls, destination: destination)
        }

        leftPanel.onDirectoryChanged = { [weak self] url in
            self?.registerRecent(url: url)
            self?.updateVolumeWarning(for: url)
            self?.refreshToolbarValidation()
            self?.updateWatcher(for: .left, directory: url)
            self?.scheduleCooperativeIndexing()
            if self?.activeSide == .left {
                self?.syncDirectoryTreeToActivePanel()
            }
        }
        rightPanel.onDirectoryChanged = { [weak self] url in
            self?.registerRecent(url: url)
            self?.updateVolumeWarning(for: url)
            self?.refreshToolbarValidation()
            self?.updateWatcher(for: .right, directory: url)
            self?.scheduleCooperativeIndexing()
            if self?.activeSide == .right {
                self?.syncDirectoryTreeToActivePanel()
            }
        }

        leftPanel.onPasteRequested = { [weak self] in
            self?.pasteItemsFromClipboardToActivePanel()
        }
        rightPanel.onPasteRequested = { [weak self] in
            self?.pasteItemsFromClipboardToActivePanel()
        }
        // v2.1.1 — acciones de contexto que coordinan ambos paneles y el estado global.
        leftPanel.onOpenInOtherPanel = { [weak self] url in
            self?.rightPanel.openURL(url)
            self?.statusLabel.stringValue = "Abierto en el panel derecho: \(url.lastPathComponent)"
        }
        rightPanel.onOpenInOtherPanel = { [weak self] url in
            self?.leftPanel.openURL(url)
            self?.statusLabel.stringValue = "Abierto en el panel izquierdo: \(url.lastPathComponent)"
        }
        leftPanel.onAddLocationRequested = { [weak self] url in self?.authorizeLocation(prefilled: url) }
        rightPanel.onAddLocationRequested = { [weak self] url in self?.authorizeLocation(prefilled: url) }
        leftPanel.onToggleFavoriteRequested = { [weak self] url in self?.toggleFavorite(for: url) }
        rightPanel.onToggleFavoriteRequested = { [weak self] url in self?.toggleFavorite(for: url) }
        leftPanel.isFavoriteProvider = { [weak self] url in
            guard let self else { return false }
            return self.favoriteStore.list().contains(url.standardizedFileURL.path)
        }
        rightPanel.isFavoriteProvider = { [weak self] url in
            guard let self else { return false }
            return self.favoriteStore.list().contains(url.standardizedFileURL.path)
        }
        leftPanel.onQuickLookRequested = { [weak self] in
            guard let self else { return }
            self.activeSide = .left
            _ = self.toggleQuickLookPreview()
        }
        rightPanel.onQuickLookRequested = { [weak self] in
            guard let self else { return }
            self.activeSide = .right
            _ = self.toggleQuickLookPreview()
        }
        leftPanel.onSearchWillStart = { [weak self] in
            self?.pauseCooperativeIndexingForSearch()
        }
        rightPanel.onSearchWillStart = { [weak self] in
            self?.pauseCooperativeIndexingForSearch()
        }
        leftPanel.onSearchDidFinish = { [weak self] in
            self?.scheduleCooperativeIndexing()
        }
        rightPanel.onSearchDidFinish = { [weak self] in
            self?.scheduleCooperativeIndexing()
        }

        // v2.0 — scope de búsqueda (⌘F) y raíces para la búsqueda global.
        leftPanel.isGlobalSearchActive = { [weak self] in self?.globalSearchScope ?? false }
        rightPanel.isGlobalSearchActive = { [weak self] in self?.globalSearchScope ?? false }
        leftPanel.indexRootsProvider = { [weak self] in self?.desiredIndexRoots() ?? [] }
        rightPanel.indexRootsProvider = { [weak self] in self?.desiredIndexRoots() ?? [] }

        // v1.1 — reanudación: si la sesión anterior murió con un trabajo activo, se ofrece rehacer los pendientes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.checkInterruptedJobs()
        }
    }

    /// ⌘L — edita la dirección en el propio panel activo (una sola barra, dentro del panel).
    @objc private func focusPathBar() {
        activePanel.beginEditingPath()
    }

    @objc private func goBack() {
        activePanel.goBack()
    }

    // MARK: - Historial con menú (Ola 2)

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === backHistoryMenu {
            rebuildHistoryMenu(menu, urls: activePanel.backHistoryURLs(), forward: false)
        } else if menu === forwardHistoryMenu {
            rebuildHistoryMenu(menu, urls: activePanel.forwardHistoryURLs(), forward: true)
        }
    }

    private func rebuildHistoryMenu(_ menu: NSMenu, urls: [URL], forward: Bool) {
        menu.removeAllItems()
        guard !urls.isEmpty else {
            let empty = NSMenuItem(title: forward ? "Sin historial adelante" : "Sin historial atrás", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }
        for url in urls {
            let item = NSMenuItem(
                title: url.path,
                action: forward ? #selector(historyForwardChosen(_:)) : #selector(historyBackChosen(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = url
            menu.addItem(item)
        }
    }

    @objc private func historyBackChosen(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        activePanel.jumpBack(to: url)
    }

    @objc private func historyForwardChosen(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        activePanel.jumpForward(to: url)
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
            statusLabel.stringValue = "No se pudo crear la carpeta: \(J4FError.from(error).userMessage)"
            NSSound.beep()
        }
    }

    @objc private func renameSelection() {
        let selected = activePanel.selectedURLs()
        guard selected.count == 1, let source = selected.first else {
            statusLabel.stringValue = "Selecciona un único elemento para renombrar en lote."
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
            statusLabel.stringValue = "No se pudo renombrar: \(J4FError.from(error).userMessage)"
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
            self.updateJobProgressStrip(snapshot, pct: pct)
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

    /// v2.1.1 — autoriza una carpeta (bookmark de sandbox). Con `prefilled` el panel de selección
    /// se abre ya situado en la carpeta propuesta (acción «Añadir a Ubicaciones» del clic derecho).
    private func authorizeLocation(prefilled: URL?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Autorizar"
        panel.message = "Selecciona una carpeta para autorizar su acceso en sandbox."
        if let prefilled {
            panel.directoryURL = prefilled.deletingLastPathComponent()
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try bookmarkStore.save(url: url)
            _ = beginSecurityScope(for: url)
            loadSidebarLocations()
            statusLabel.stringValue = "Ubicacion autorizada guardada: \(url.lastPathComponent)"
        } catch {
            statusLabel.stringValue = "Error al guardar bookmark: \(J4FError.from(error).userMessage)"
            NSSound.beep()
        }
    }

    /// v2.1.1 — añade o quita una carpeta de Favoritos (menú contextual del panel).
    private func toggleFavorite(for url: URL) {
        let path = url.standardizedFileURL.path
        if favoriteStore.list().contains(path) {
            favoriteStore.remove(path: path)
            statusLabel.stringValue = "Favorito quitado: \(url.lastPathComponent)"
        } else {
            favoriteStore.add(path: path)
            statusLabel.stringValue = "Favorito añadido: \(url.lastPathComponent)"
        }
        favoriteLocations = favoriteStore.list().map { URL(fileURLWithPath: $0) }
        favoritesTable.reloadData()
    }

    @objc private func searchChanged(_ sender: NSSearchField) {
        // v2.0 — vaciar el campo restaura el scope normal (⌘F vuelve a activar el global).
        if sender.stringValue.trimmingCharacters(in: .whitespaces).isEmpty, globalSearchScope {
            setGlobalSearchScope(false, announce: false)
        }
        activePanel.setSearchQuery(sender.stringValue)
    }

    // MARK: - Búsqueda global (v2.0)

    @objc private func toggleGlobalSearchScope() {
        setGlobalSearchScope(!globalSearchScope, announce: true)
    }

    /// Alterna entre «buscar en esta carpeta» y «buscar en todo el índice» (⌘F).
    private func setGlobalSearchScope(_ enabled: Bool, announce: Bool) {
        if globalSearchScope != enabled {
            globalSearchScope = enabled
            searchField.placeholderString = enabled ? "Buscar en todo el índice…" : "Buscar en esta carpeta…"
            searchField.toolTip = enabled
                ? "Búsqueda global: abarca todas las ubicaciones indexadas."
                : "Búsqueda en la carpeta actual. Pulsa ⌘F para buscar en todo el índice."
            searchField.setAccessibilityLabel(enabled ? "Busqueda global" : "Busqueda rapida")
            if announce {
                statusLabel.stringValue = enabled
                    ? "Búsqueda global activa: la consulta abarca todas las ubicaciones indexadas (⌘F vuelve a «esta carpeta»)."
                    : "Búsqueda en la carpeta actual (⌘F busca en todo el índice)."
            }
            activePanel.rerunSearchNow()
        }
        view.window?.makeFirstResponder(searchField)
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
            statusLabel.stringValue = "No se pudo exportar diagnostico: \(J4FError.from(error).userMessage)"
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
        if !report.failedLocations.isEmpty {
            logger.warning("Bookmarks sin resolver: \(report.failedLocations.map(\.path).joined(separator: ", "), privacy: .public)")
        }
        updateReauthSectionVisibility()
        sidebarLocationsEmptyHint?.isHidden = !authorizedLocations.isEmpty
        for url in authorizedLocations {
            _ = beginSecurityScope(for: url)
        }
        authorizedTable.reloadData()
        favoritesTable.reloadData()
        recentsTable.reloadData()
        reauthTable.reloadData()
        updateWatchersForVisibleDirectories()
        scheduleCooperativeIndexing()

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
            statusLabel.stringValue = "No se pudo reautorizar: \(J4FError.from(error).userMessage)"
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
            refreshBottomStackHeight()
            return
        }

        if info.isReadOnly {
            volumeWarningLabel.stringValue = "Volumen en solo lectura (\(info.fileSystemType)). Algunas operaciones de escritura no estaran disponibles."
            volumeWarningLabel.isHidden = false
            refreshBottomStackHeight()
            return
        }

        if info.isLikelyNTFS {
            volumeWarningLabel.stringValue = "Volumen NTFS detectado. Escritura puede depender de drivers externos."
            volumeWarningLabel.isHidden = false
            refreshBottomStackHeight()
            return
        }

        volumeWarningLabel.isHidden = true
        volumeWarningLabel.stringValue = ""
        refreshBottomStackHeight()
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
        activeIndicatorLabel.stringValue = activeSide == .left ? "IZQ" : "DER"
        activeIndicatorLabel.toolTip = "Panel activo: \(activeSide.rawValue) · Tab cambia"
        leftPanel.setActive(activeSide == .left)
        rightPanel.setActive(activeSide == .right)
    }

    private func refreshToolbarValidation() {
        view.window?.toolbar?.validateVisibleItems()
    }

    private func toggleActivePanel() {
        captureDirectoryTreeState(for: activeSide)
        activeSide = (activeSide == .left) ? .right : .left
        activePanel.focusTable()
        refreshToolbarValidation()
        syncDirectoryTreeToActivePanel()
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
                Task {
                    let indexed = await self.indexedSearch.isIndexed(for: directory)
                    if indexed {
                        await self.indexedSearch.refreshChangedPaths(changedPaths, watchedRoot: directory, includeHidden: self.preferences.showHiddenFiles)
                    }
                }
            }
            watcher.setPaused(!activeJobIds.isEmpty)
        } catch {
            statusLabel.stringValue = "No se pudo vigilar «\(directory.lastPathComponent)»: \(J4FError.from(error).userMessage)"
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

    @objc private func goHome() {
        activePanel.openURL(homeDirectoryURL)
    }

    private func applyPreferences(initial: Bool) {
        preferences = J4FPreferences.load()
        leftPanel.setIncludeHidden(preferences.showHiddenFiles)
        rightPanel.setIncludeHidden(preferences.showHiddenFiles)
        BufferSizer.shared.setPreferredBigBytes(preferences.preferredBigBufferMB * 1024 * 1024)
        syncDirectoryTreeToActivePanel()
        scheduleCooperativeIndexing()
        applyVisualStyle(preferences.visualStyle)

        if !initial {
            statusLabel.stringValue = "Preferencias aplicadas. Estilo: \(preferences.visualStyle.title)."
        }
    }

    /// v2.1.1 — estilo visual (Ajustes ▸ Apariencia): reaplica los acentos de marca en vivo.
    private func applyVisualStyle(_ style: J4FVisualStyle) {
        J4FDesign.currentStyle = style
        activeIndicatorLabel.textColor = J4FDesign.brand
        activeIndicatorLabel.layer?.backgroundColor = J4FDesign.brandSoft.cgColor
        leftPanel.reapplyBrandStyle()
        rightPanel.reapplyBrandStyle()
        // La barra lateral tinta iconos con el color de marca (se reconstruye con el nuevo).
        loadSidebarLocations()
    }

    private func scheduleCooperativeIndexing() {
        if isCooperativeIndexing {
            return
        }
        cooperativeIndexDebounceWorkItem?.cancel()
        let roots = desiredIndexRoots()
        let includeHidden = preferences.showHiddenFiles

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.cooperativeIndexTask?.cancel()
            self.isCooperativeIndexing = true
            self.cooperativeIndexTask = Task.detached(priority: .utility) { [weak self] in
                guard let self else { return }
                do {
                    try await self.indexedSearch.ensureIndexedCooperative(
                        roots: roots,
                        includeHidden: includeHidden,
                        batchSize: 400,
                        pausePerBatchMS: 20,
                        onProgress: { [weak self] displayPath, scanned in
                            Task { @MainActor in
                                self?.updateIndexProgress(displayPath: displayPath, scanned: scanned)
                            }
                        }
                    )
                    await MainActor.run {
                        self.isCooperativeIndexing = false
                        self.flashIndexingCompleteHighlight()
                    }
                } catch {
                    await MainActor.run {
                        self.isCooperativeIndexing = false
                    }
                }
            }
        }
        cooperativeIndexDebounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private func desiredIndexRoots() -> [URL] {
        var roots: [URL] = [leftPanel.currentDirectoryURL, rightPanel.currentDirectoryURL]
        roots.append(contentsOf: authorizedLocations)
        let unique = Set(roots.map { $0.standardizedFileURL.path })
        return unique.sorted().map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    private func flashIndexingCompleteHighlight() {
        leftPanel.flashIndexReady()
        rightPanel.flashIndexReady()
        statusLabel.stringValue = "Indexado incremental completado."
    }

    /// v2.0 — estado en vivo del crawl cooperativo: «Indexando «ruta»: N entradas…» (4/s máx).
    private func updateIndexProgress(displayPath: String, scanned: Int64) {
        let now = Date()
        guard now.timeIntervalSince(lastIndexProgressUpdate) > 0.25 else { return }
        lastIndexProgressUpdate = now
        logger.debug("Progreso de indexado «\(displayPath, privacy: .public)»: \(scanned) entrada(s).")
        statusLabel.stringValue = "Indexando «\(displayPath)»: \(scanned.formatted()) entrada(s)…"
    }

    // MARK: - Reanudación tras caída (v1.1)

    /// Si la sesión anterior murió con un trabajo a medias (snapshot «running/paused» + diario de
    /// items), ofrece re-encolar los pendientes. Los elementos ya movidos/copiados (origen ausente)
    /// se omiten y los conflictos se resuelven renombrando (nunca se sobrescribe).
    private func checkInterruptedJobs() {
        let interrupted = jobQueue.interruptedJobs()
        guard let primary = interrupted.first else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Se interrumpió un trabajo de \(primary.snapshot.type.rawValue)"
        alert.informativeText = "Se detectó un trabajo sin terminar de la sesión anterior (\(primary.snapshot.processedItems)/\(primary.snapshot.totalItems) elementos procesados). Al reanudar se omiten los ya hechos y los conflictos se renombran."
        alert.addButton(withTitle: "Reanudar pendientes")
        alert.addButton(withTitle: "Descartar")
        alert.addButton(withTitle: "Más tarde")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            var resumed = 0
            for job in interrupted {
                let outcome = jobQueue.requeueInterrupted(
                    snapshot: job.snapshot,
                    items: job.items,
                    options: currentJobOptions()
                ) { [weak self] snapshot in
                    guard let self else { return }
                    let pct = Int(snapshot.progress * 100)
                    self.statusLabel.stringValue = "[REANUDAR] \(snapshot.processedItems)/\(snapshot.totalItems) (\(pct)%) - \(snapshot.state.rawValue)"
                    if snapshot.state == .done || snapshot.state == .failed || snapshot.state == .cancelled {
                        self.leftPanel.refreshCurrentDirectory()
                        self.rightPanel.refreshCurrentDirectory()
                    }
                }
                if let outcome {
                    resumed += outcome.itemCount
                }
            }
            statusLabel.stringValue = resumed > 0
                ? "Reanudados \(resumed) elemento(s) pendientes."
                : "No quedaban pendientes por reanudar."
        case .alertSecondButtonReturn:
            for job in interrupted {
                jobQueue.discardPersisted(jobId: job.snapshot.id)
            }
            statusLabel.stringValue = "Trabajos interrumpidos descartados."
        default:
            statusLabel.stringValue = "Hay trabajos interrumpidos: se volverá a preguntar en el próximo arranque."
        }
    }

    private func currentJobOptions() -> JobExecutionOptions {
        JobExecutionOptions(deletePreference: preferences.deleteBehavior.deletePreference)
    }

    private func pauseCooperativeIndexingForSearch() {
        cooperativeIndexDebounceWorkItem?.cancel()
        cooperativeIndexTask?.cancel()
        isCooperativeIndexing = false
    }

    private func reloadDirectoryTree(root: URL) {
        isUpdatingDirectoryTreeSelection = true
        defer { isUpdatingDirectoryTreeSelection = false }
        let rootNode = DirectoryTreeNode(url: root)
        directoryTreeRoot = rootNode
        directoryTree.reloadData()
        if directoryTree.numberOfRows > 0 {
            directoryTree.expandItem(rootNode)
        }
    }

    private func syncDirectoryTreeToActivePanel() {
        let current = activePanel.currentDirectoryURL.standardizedFileURL
        let desiredRoot: URL
        if current.path == homeDirectoryURL.path || current.path.hasPrefix(homeDirectoryURL.path + "/") {
            desiredRoot = homeDirectoryURL
        } else if let volumeURL = try? current.resourceValues(forKeys: [.volumeURLKey]).volume {
            desiredRoot = volumeURL.standardizedFileURL
        } else {
            desiredRoot = URL(fileURLWithPath: "/", isDirectory: true)
        }

        if directoryTreeRoot?.url.standardizedFileURL.path != desiredRoot.path {
            reloadDirectoryTree(root: desiredRoot)
        }
        restoreDirectoryTreeState(for: activeSide)
        selectInDirectoryTree(path: current)
    }

    private func captureDirectoryTreeState(for side: PanelSide) {
        var expanded: Set<String> = []
        for row in 0..<directoryTree.numberOfRows {
            guard let node = directoryTree.item(atRow: row) as? DirectoryTreeNode else { continue }
            if directoryTree.isItemExpanded(node) {
                expanded.insert(node.url.standardizedFileURL.path)
            }
        }
        expandedTreePathsBySide[side] = expanded
        let selectedRow = directoryTree.selectedRow
        if selectedRow >= 0, let selected = directoryTree.item(atRow: selectedRow) as? DirectoryTreeNode {
            selectedTreePathBySide[side] = selected.url.standardizedFileURL.path
        }
    }

    private func restoreDirectoryTreeState(for side: PanelSide) {
        guard let root = directoryTreeRoot else { return }
        let expanded = expandedTreePathsBySide[side] ?? []
        for path in expanded {
            guard path != root.url.standardizedFileURL.path else { continue }
            _ = expandPathInTree(path)
        }
        if let selectedPath = selectedTreePathBySide[side],
           let selectedNode = findNodeInTree(path: selectedPath) {
            let row = directoryTree.row(forItem: selectedNode)
            if row >= 0 {
                isUpdatingDirectoryTreeSelection = true
                directoryTree.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                isUpdatingDirectoryTreeSelection = false
            }
        }
    }

    @discardableResult
    private func expandPathInTree(_ path: String) -> DirectoryTreeNode? {
        guard let root = directoryTreeRoot else { return nil }
        let rootPath = root.url.standardizedFileURL.path
        guard path == rootPath || path.hasPrefix(rootPath + "/") else { return nil }
        if path == rootPath {
            directoryTree.expandItem(root)
            return root
        }

        var node = root
        let rootComponents = root.url.standardizedFileURL.pathComponents
        let targetComponents = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
        let remainder = targetComponents.dropFirst(rootComponents.count)
        for component in remainder {
            loadChildrenIfNeeded(for: node)
            guard let next = node.children.first(where: { !$0.isParentShortcut && $0.url.lastPathComponent == component }) else {
                return nil
            }
            directoryTree.expandItem(node)
            node = next
        }
        return node
    }

    private func findNodeInTree(path: String) -> DirectoryTreeNode? {
        expandPathInTree(path)
    }

    private func selectInDirectoryTree(path target: URL) {
        guard let root = directoryTreeRoot else { return }
        let rootPath = root.url.standardizedFileURL.path
        let targetPath = target.standardizedFileURL.path

        guard targetPath == rootPath || targetPath.hasPrefix(rootPath + "/") else {
            let rootRow = directoryTree.row(forItem: root)
            if rootRow >= 0 {
                isUpdatingDirectoryTreeSelection = true
                directoryTree.selectRowIndexes(IndexSet(integer: rootRow), byExtendingSelection: false)
                isUpdatingDirectoryTreeSelection = false
            }
            return
        }

        if targetPath == rootPath {
            let row = directoryTree.row(forItem: root)
            if row >= 0 {
                isUpdatingDirectoryTreeSelection = true
                directoryTree.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                isUpdatingDirectoryTreeSelection = false
            }
            return
        }

        var node = root
        let rootComponents = root.url.standardizedFileURL.pathComponents
        let targetComponents = target.standardizedFileURL.pathComponents
        let remainder = targetComponents.dropFirst(rootComponents.count)

        for component in remainder {
            loadChildrenIfNeeded(for: node)
            guard let next = node.children.first(where: { !$0.isParentShortcut && $0.url.lastPathComponent == component }) else { break }
            directoryTree.expandItem(node)
            node = next
        }

        let row = directoryTree.row(forItem: node)
        if row >= 0 {
            isUpdatingDirectoryTreeSelection = true
            directoryTree.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            directoryTree.scrollRowToVisible(row)
            isUpdatingDirectoryTreeSelection = false
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
        guard let node = item as? DirectoryTreeNode else { return DirectoryTreeNode(url: activePanel.currentDirectoryURL) }
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
        if isUpdatingDirectoryTreeSelection { return }
        guard let outline = notification.object as? NSOutlineView, outline == directoryTree else { return }
        let row = outline.selectedRow
        guard row >= 0, let node = outline.item(atRow: row) as? DirectoryTreeNode else { return }
        if node.url.standardizedFileURL.path == activePanel.currentDirectoryURL.standardizedFileURL.path {
            return
        }
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
            return DirectoryTreeNode(url: entry, parent: node)
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

    /// v2.0 — ejecuta un comando de atajo configurable (devuelve false si no aplica).
    private func performShortcutCommand(_ command: String) -> Bool {
        switch command {
        case "rename": renameSelection()
        case "quickLook": _ = toggleQuickLookPreview()
        case "openEdit": activePanel.openSelection()
        case "copy": copySelection()
        case "move": moveSelection()
        case "mkdir": createDirectory()
        case "delete": deleteSelection()
        case "newTab": newTab()
        case "closeTab": closeTabOrWindow()
        case "selectAll": activePanel.selectAllItems()
        case "paste": pasteItemsFromClipboardToActivePanel()
        case "duplicateTab": onDuplicateTabRequested()
        default: return false
        }
        return true
    }

    private func handleKeyShortcut(_ event: NSEvent) -> Bool {
        guard view.window?.isKeyWindow == true else { return false }
        if NSApp.modalWindow != nil || view.window?.attachedSheet != nil {
            return false
        }

        // v2.0 — ⌘F: alterna «esta carpeta ⇄ todo el índice» (también con el buscador activo).
        if event.keyCode == 3,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command] {
            if isEditingTextInput {
                let editor = view.window?.firstResponder as? NSTextView
                if (editor?.delegate as? NSSearchField) !== searchField {
                    return false
                }
            }
            toggleGlobalSearchScope()
            return true
        }

        if isEditingTextInput {
            return false
        }

        // v1.2 — filtro rápido: escribir sobre una tabla filtra; ⌫ borra; Esc limpia.
        if let panel = panelOwningTableFirstResponder(), flagsEither([[], [.shift]], event) {
            if event.keyCode == 53 { // Esc
                if panel.hasQuickFilter {
                    panel.clearQuickFilter()
                    return true
                }
            } else if event.keyCode == 51 { // ⌫
                if panel.hasQuickFilter {
                    panel.removeQuickFilterLastCharacter()
                    return true
                }
            } else if let chars = event.characters, !chars.isEmpty,
                      chars.unicodeScalars.allSatisfy({ scalar in
                          scalar.value >= 0x21 && scalar.value != 0x7F
                              && !(scalar.value >= 0xF700 && scalar.value <= 0xF8FF)
                      }) {
                panel.appendQuickFilter(chars)
                return true
            }
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // v2.0 — atajos configurables (shortcuts.json): se resuelven antes de los por defecto.
        if let command = ShortcutStore.shared.command(
            keyCode: event.keyCode,
            flags: (flags.contains(.command), flags.contains(.option), flags.contains(.shift), flags.contains(.control))
        ), performShortcutCommand(command) {
            return true
        }

        if flags == [] {
            switch event.keyCode {
            case 36, 76: // Return / Enter
                if openSelectedSidebarIfFocused() {
                    return true
                }
            case 49: // Espacio — QuickLook (Ola 1)
                if toggleQuickLookPreview() {
                    return true
                }
            case 48: // Tab
                if view.window?.firstResponder is NSTextView {
                    return false
                }
                toggleActivePanel()
                return true
            case 120: // F2 — renombrar
                renameSelection()
                return true
            case 99: // F3 — QuickLook
                if toggleQuickLookPreview() {
                    return true
                }
            case 118: // F4 — abrir (editar con la app por defecto)
                activePanel.openSelection()
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
            if chars == "c" {
                activePanel.copySelectionToClipboard()
                return true
            }
            if chars == "x" {
                activePanel.cutSelectionToClipboard()
                return true
            }
            if chars == "v" {
                pasteItemsFromClipboardToActivePanel()
                return true
            }
            if chars == "d" {
                activePanel.duplicateSelection()
                return true
            }
            if chars == "\\" {
                toggleSinglePanelMode()
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

    /// ¿Qué panel tiene la tabla con el foco? (para el filtro rápido)
    private func panelOwningTableFirstResponder() -> FilePanelViewController? {
        if leftPanel.isTableFirstResponder() { return leftPanel }
        if rightPanel.isTableFirstResponder() { return rightPanel }
        return nil
    }

    // MARK: - QuickLook (Ola 1)

    /// Abre/cierra el panel de QuickLook para la selección del panel con foco.
    private func toggleQuickLookPreview() -> Bool {
        guard let source = panelOwningTableFirstResponder() ?? previewPanelSource else { return false }
        guard !source.selectedURLs().isEmpty else { return false }
        previewPanelSource = source

        if QLPreviewPanel.sharedPreviewPanelExists(),
           let panel = QLPreviewPanel.shared(), panel.isVisible {
            panel.orderOut(nil)
            return true
        }
        guard let panel = QLPreviewPanel.shared() else { return false }
        panel.makeKeyAndOrderFront(nil)
        return true
    }

    /// Refresca el preview cuando cambia la selección del panel que lo alimenta.
    fileprivate func previewSourceSelectionChanged(_ source: FilePanelViewController) {
        updatePreviewPane()
        guard source === previewPanelSource,
              QLPreviewPanel.sharedPreviewPanelExists(),
              QLPreviewPanel.shared()?.isVisible == true else { return }
        QLPreviewPanel.shared()?.reloadData()
    }

    // MARK: - Vista previa lateral (Ola 2)

    private func configurePreviewPane() {
        previewPane.translatesAutoresizingMaskIntoConstraints = false
        J4FDesign.styleCard(previewPane, radius: J4FDesign.Radius.medium)
        previewPane.isHidden = !previewPaneVisible
        previewPane.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true

        // v2.3 (Panel Hub F1) — selector de módulo: Vista previa | DESK mini.
        previewModuleSelector.translatesAutoresizingMaskIntoConstraints = false
        previewModuleSelector.controlSize = .small
        previewModuleSelector.segmentStyle = .rounded
        previewModuleSelector.segmentDistribution = .fillEqually
        previewModuleSelector.target = self
        previewModuleSelector.action = #selector(onPreviewModuleChanged(_:))
        previewModuleSelector.setAccessibilityLabel("Modulo del panel lateral")

        previewContentHost.translatesAutoresizingMaskIntoConstraints = false

        let ql = QLPreviewView(frame: .zero, style: .normal)
        ql?.autostarts = true
        ql?.translatesAutoresizingMaskIntoConstraints = false
        previewView = ql

        previewInfoLabel.font = J4FDesign.captionFont()
        previewInfoLabel.textColor = .secondaryLabelColor
        previewInfoLabel.alignment = .center
        previewInfoLabel.lineBreakMode = .byWordWrapping
        previewInfoLabel.maximumNumberOfLines = 0
        previewInfoLabel.translatesAutoresizingMaskIntoConstraints = false

        // v2.1 — estado vacío con icono (antes la tarjeta quedaba en blanco absoluto).
        previewPlaceholderIcon.image = NSImage(systemSymbolName: "eye", accessibilityDescription: nil)
        previewPlaceholderIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 26, weight: .light)
        previewPlaceholderIcon.contentTintColor = .tertiaryLabelColor
        previewPlaceholderIcon.translatesAutoresizingMaskIntoConstraints = false

        // Importante: la etiqueta debe estar ANTES en la jerarquía (las constraints no pueden
        // cruzar vistas sin ancestro común).
        previewContentHost.addSubview(previewInfoLabel)
        previewContentHost.addSubview(previewPlaceholderIcon)
        if let ql {
            previewContentHost.addSubview(ql)
            NSLayoutConstraint.activate([
                ql.leadingAnchor.constraint(equalTo: previewContentHost.leadingAnchor),
                ql.trailingAnchor.constraint(equalTo: previewContentHost.trailingAnchor),
                ql.topAnchor.constraint(equalTo: previewContentHost.topAnchor),
                ql.bottomAnchor.constraint(equalTo: previewInfoLabel.topAnchor, constant: -6)
            ])
        }
        NSLayoutConstraint.activate([
            previewInfoLabel.leadingAnchor.constraint(equalTo: previewContentHost.leadingAnchor, constant: 4),
            previewInfoLabel.trailingAnchor.constraint(equalTo: previewContentHost.trailingAnchor, constant: -4),
            previewInfoLabel.bottomAnchor.constraint(equalTo: previewContentHost.bottomAnchor, constant: -4),
            previewPlaceholderIcon.centerXAnchor.constraint(equalTo: previewContentHost.centerXAnchor),
            previewPlaceholderIcon.centerYAnchor.constraint(equalTo: previewContentHost.centerYAnchor, constant: -8)
        ])

        deskMiniPanel.onOpenURL = { [weak self] url in self?.openFromDeskMini(url) }
        deskMiniPanel.onOrderFolder = { [weak self] url in self?.openOrdering(for: url) }
        deskMiniPanel.searchProvider = { [weak self] query in self?.performDeskMiniSearch(query) }
        deskMiniPanel.onDropFiles = { [weak self] urls in self?.proposeDestination(for: urls) }
        pictMiniPanel.onStatus = { [weak self] message in self?.statusLabel.stringValue = message }
        pictMiniPanel.onCreatedFiles = { [weak self] in
            self?.leftPanel.reloadAfterExternalChange()
            self?.rightPanel.reloadAfterExternalChange()
        }

        previewPane.addSubview(previewModuleSelector)
        previewPane.addSubview(previewContentHost)
        previewPane.addSubview(deskMiniPanel)
        previewPane.addSubview(pictMiniPanel)
        NSLayoutConstraint.activate([
            // v2.3 — la toolbar (fullSizeContentView) tapa los primeros ~38pt de la ventana:
            // el contenido del panel arranca debajo para que el selector sea visible.
            previewModuleSelector.topAnchor.constraint(equalTo: previewPane.topAnchor, constant: 44),
            previewModuleSelector.leadingAnchor.constraint(equalTo: previewPane.leadingAnchor, constant: 6),
            previewModuleSelector.trailingAnchor.constraint(equalTo: previewPane.trailingAnchor, constant: -6),

            previewContentHost.topAnchor.constraint(equalTo: previewModuleSelector.bottomAnchor, constant: 6),
            previewContentHost.leadingAnchor.constraint(equalTo: previewPane.leadingAnchor, constant: 6),
            previewContentHost.trailingAnchor.constraint(equalTo: previewPane.trailingAnchor, constant: -6),
            previewContentHost.bottomAnchor.constraint(equalTo: previewPane.bottomAnchor, constant: -6),

            deskMiniPanel.topAnchor.constraint(equalTo: previewContentHost.topAnchor),
            deskMiniPanel.leadingAnchor.constraint(equalTo: previewContentHost.leadingAnchor),
            deskMiniPanel.trailingAnchor.constraint(equalTo: previewContentHost.trailingAnchor),
            deskMiniPanel.bottomAnchor.constraint(equalTo: previewContentHost.bottomAnchor),

            pictMiniPanel.topAnchor.constraint(equalTo: previewContentHost.topAnchor),
            pictMiniPanel.leadingAnchor.constraint(equalTo: previewContentHost.leadingAnchor),
            pictMiniPanel.trailingAnchor.constraint(equalTo: previewContentHost.trailingAnchor),
            pictMiniPanel.bottomAnchor.constraint(equalTo: previewContentHost.bottomAnchor)
        ])

        applyPreviewModule()
    }

    /// v2.3 (Panel Hub F1) — cambia el módulo del panel lateral (Vista previa | DESK | PICT).
    @objc private func onPreviewModuleChanged(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 1: previewModule = "desk"
        case 2: previewModule = "pict"
        default: previewModule = "preview"
        }
        applyPreviewModule()
        if previewModule == "desk" {
            deskMiniPanel.focusSearch()
        }
    }

    /// Aplica el módulo guardado y sincroniza selector/contenido.
    private func applyPreviewModule() {
        // v2.3.4 — normaliza: PICT no puede estar activo sin imágenes en la selección
        // (si quedó persistido «pict» sin selección usable, se vuelve a «Vista previa»).
        if previewModule == "pict", PictQuickActions.images(in: activePanel.selectedURLs()).isEmpty {
            previewModule = "preview"
        }
        let desk = previewModule == "desk"
        let pict = previewModule == "pict"
        updateModuleSelectorSegments()
        previewContentHost.isHidden = desk || pict
        deskMiniPanel.isHidden = !desk
        pictMiniPanel.isHidden = !pict
        UserDefaults.standard.set(previewModule, forKey: "j4f.previewModule")
        if desk {
            deskMiniPanel.refreshInbox()
            refreshDeskReview()
            statusLabel.stringValue = "Módulo DESK: bandeja + buscador del índice (suelta documentos aquí para archivarlos)."
        } else if pict {
            refreshPictSelection()
            statusLabel.stringValue = "Módulo PICT: acciones rápidas sobre la imagen seleccionada."
        } else {
            updatePreviewPane()
        }
    }

    /// v2.3.2 (F3) — sincroniza la selección del panel activo con el módulo PICT.
    private func refreshPictSelection() {
        pictMiniPanel.updateSelection(activePanel.selectedURLs())
    }

    /// v2.3.4 — el módulo PICT solo existe cuando la selección del panel activo tiene imágenes:
    /// si estaba activo y la selección deja de ser usable, se vuelve a «Vista previa».
    private func refreshPictAvailability() {
        let hasImages = !PictQuickActions.images(in: activePanel.selectedURLs()).isEmpty
        if !hasImages, previewModule == "pict" {
            previewModule = "preview"
            statusLabel.stringValue = "PICT se oculta sin imágenes en la selección; vuelto a Vista previa."
            applyPreviewModule()
        } else {
            updateModuleSelectorSegments()
        }
    }

    /// Sincroniza los segmentos del selector con la disponibilidad actual del módulo PICT.
    private func updateModuleSelectorSegments() {
        let hasImages = !PictQuickActions.images(in: activePanel.selectedURLs()).isEmpty
        let targetCount = hasImages ? 3 : 2
        if previewModuleSelector.segmentCount != targetCount {
            previewModuleSelector.segmentCount = targetCount
            previewModuleSelector.setLabel("Vista previa", forSegment: 0)
            previewModuleSelector.setLabel("DESK", forSegment: 1)
            if hasImages {
                previewModuleSelector.setLabel("PICT", forSegment: 2)
            }
        }
        switch previewModule {
        case "desk": previewModuleSelector.selectedSegment = 1
        case "pict": previewModuleSelector.selectedSegment = hasImages ? 2 : 0
        default: previewModuleSelector.selectedSegment = 0
        }
    }

    /// Búsqueda global del índice para el módulo DESK (mismo servicio que ⌘F).
    private func performDeskMiniSearch(_ query: String) {
        Task { [weak self] in
            let hits = (try? await IndexedSearchService.shared.searchGlobal(query: query, limit: 300)) ?? []
            await MainActor.run { [weak self] in
                self?.deskMiniPanel.presentSearchResults(hits, for: query)
            }
        }
    }

    /// Abrir desde el módulo DESK: carpetas en el panel activo; ficheros, con su app por defecto.
    private func openFromDeskMini(_ url: URL) {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        guard exists else {
            statusLabel.stringValue = "Ya no existe: \(url.lastPathComponent)"
            NSSound.beep()
            return
        }
        if isDirectory.boolValue {
            activePanel.openPath(url.path)
            statusLabel.stringValue = "Abierto \(url.lastPathComponent) en el panel activo."
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    /// v2.3 (F2) — cola «por revisar»: dudosos en 99_SinClasificar del último destino de ordenación.
    private func refreshDeskReview() {
        guard let path = UserDefaults.standard.string(forKey: "j4f.lastOrderingDestination") else {
            deskMiniPanel.updateReview(count: 0, folderName: nil, folder: nil)
            return
        }
        let root = URL(fileURLWithPath: path, isDirectory: true)
        let items = QuarantineListing.itemURLs(rootURL: root)
        let strays = root.appendingPathComponent(DefaultTaxonomy.quarantineRelativePath, isDirectory: true)
        let folder = FileManager.default.fileExists(atPath: strays.path) ? strays : nil
        deskMiniPanel.updateReview(count: items.count, folderName: root.lastPathComponent, folder: folder)
    }

    // MARK: - F3: propuesta de destino al soltar documentos en el módulo DESK

    /// v2.3.2 (F3) — soltar documentos sobre el módulo: propone categoría (reglas + taxonomía
    /// compartidas de DESK) y, tras confirmar, los MUEVE con la cola de trabajos (nunca borra).
    private func proposeDestination(for urls: [URL]) {
        let files = urls.filter { url in
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            return exists && !isDirectory.boolValue
        }
        guard !files.isEmpty else {
            statusLabel.stringValue = "Suelta ficheros (no carpetas) para proponerles destino."
            NSSound.beep()
            return
        }

        let parent = files[0].deletingLastPathComponent()
        let remembered = rememberedDestination(for: parent)
        let lastUsed = UserDefaults.standard.string(forKey: "j4f.lastOrderingDestination")
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
        let root = remembered ?? lastUsed ?? parent

        let items = FolderOrderer.plan(files: files)
        var groups: [String: [FolderOrderer.Item]] = [:]
        for item in items {
            if let relative = item.destinationRelativePath {
                groups[relative, default: []].append(item)
            }
        }
        guard !groups.isEmpty else {
            statusLabel.stringValue = "Nada que proponer para ese tipo de ficheros."
            return
        }

        let total = groups.values.reduce(0) { $0 + $1.count }
        var lines: [String] = []
        for (relative, grouped) in groups.sorted(by: { $0.key < $1.key }) {
            let reason = grouped.first?.reason ?? ""
            if grouped.count == 1, let item = grouped.first {
                lines.append("• \(item.url.lastPathComponent) → \(relative)/\(item.finalName ?? "")  (\(reason))")
            } else {
                lines.append("• \(grouped.count) ficheros → \(relative)/  (\(reason))")
            }
        }
        let body = lines.prefix(8).joined(separator: "\n") + (lines.count > 8 ? "\n…" : "")

        let alert = NSAlert()
        alert.messageText = "Archivar \(total) documento(s) en \(root.lastPathComponent)"
        alert.informativeText = body + "\n\nLos ficheros se moverán (nunca se borran); en colisión se renombra."
        alert.addButton(withTitle: "Mover")
        alert.addButton(withTitle: "Cancelar")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        for (relative, grouped) in groups {
            let destination = root.appendingPathComponent(relative, isDirectory: true)
            try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            enqueueFileJob(type: .move, selected: grouped.map(\.url), destination: destination)
        }
        statusLabel.stringValue = "Archivando \(total) documento(s) en \(root.lastPathComponent)…"
    }

    /// v2.3.2 (F3) — destino recordado por carpeta (mapa carpeta → destino en UserDefaults).
    private func rememberedDestination(for folder: URL) -> URL? {
        let map = UserDefaults.standard.dictionary(forKey: "j4f.folderDestinations") as? [String: String]
        guard let path = map?[folder.standardizedFileURL.path] else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private func rememberDestination(_ destination: URL, for folder: URL) {
        var map = (UserDefaults.standard.dictionary(forKey: "j4f.folderDestinations") as? [String: String]) ?? [:]
        map[folder.standardizedFileURL.path] = destination.standardizedFileURL.path
        UserDefaults.standard.set(map, forKey: "j4f.folderDestinations")
    }

    private func togglePreviewPane() {
        previewPaneVisible.toggle()
        previewPane.isHidden = !previewPaneVisible
        UserDefaults.standard.set(previewPaneVisible, forKey: "j4f.previewPaneVisible")
        updatePreviewPane()
        statusLabel.stringValue = previewPaneVisible ? "Vista previa activada." : "Vista previa ocultada."
    }

    private func updatePreviewPane() {
        if previewModule == "pict" {
            refreshPictSelection()
        }
        refreshPictAvailability()
        guard previewPaneVisible, let ql = previewView else { return }
        let selected = activePanel.selectedURLs()
        let url = selected.count == 1 ? selected.first : nil
        ql.previewItem = url as NSURL?
        ql.isHidden = (url == nil)

        guard let url else {
            // v2.1 — estado vacío claro en vez de tarjeta en blanco.
            previewPlaceholderIcon.isHidden = false
            previewInfoLabel.stringValue = selected.isEmpty
                ? "Selecciona un archivo para la vista previa\n⌥⌘P oculta este panel"
                : "\(selected.count) elementos seleccionados"
            return
        }
        previewPlaceholderIcon.isHidden = true
        var lines: [String] = [url.lastPathComponent]
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey, .localizedTypeDescriptionKey])
        if let type = values?.localizedTypeDescription {
            lines.append(type)
        }
        if let size = values?.fileSize, values?.isDirectory != true {
            lines.append(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
        }
        if let date = values?.contentModificationDate {
            lines.append(date.formatted(date: .abbreviated, time: .shortened))
        }
        let tags = FinderTags.names(of: url)
        if !tags.isEmpty {
            lines.append("Etiquetas: " + tags.joined(separator: ", "))
        }
        previewInfoLabel.stringValue = lines.joined(separator: "\n")
    }

    /// Ola 2 — barra de progreso del trabajo en curso (se oculta al terminar).
    private func updateJobProgressStrip(_ snapshot: JobSnapshot, pct: Int) {
        let finished = snapshot.state == .done || snapshot.state == .failed || snapshot.state == .cancelled
        jobProgressBar.isHidden = finished
        jobProgressLabel.isHidden = finished
        (jobProgressBar.superview as? NSStackView)?.isHidden = finished
        refreshBottomStackHeight()
        guard !finished else {
            // v2.3 (F2) — la actividad del módulo DESK refleja el mismo trabajo.
            deskMiniPanel.updateActivity(text: nil, progress: nil)
            return
        }
        jobProgressBar.doubleValue = max(0, min(1, snapshot.progress))
        jobProgressLabel.stringValue = "\(snapshot.type.rawValue.uppercased()) \(snapshot.processedItems)/\(snapshot.totalItems) (\(pct)%)"
        deskMiniPanel.updateActivity(text: jobProgressLabel.stringValue, progress: snapshot.progress)
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel) {
        panel.dataSource = self
        panel.delegate = self
        previewPanelSource = panelOwningTableFirstResponder() ?? activePanel
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel) {
        panel.dataSource = nil
        panel.delegate = nil
    }

    @objc func numberOfPreviewItems(in panel: QLPreviewPanel) -> Int {
        previewPanelSource?.selectedURLs().count ?? 0
    }

    @objc func previewPanel(_ panel: QLPreviewPanel, previewItemAt index: Int) -> QLPreviewItem {
        let urls = previewPanelSource?.selectedURLs() ?? []
        guard index >= 0, index < urls.count else { return NSURL(fileURLWithPath: "/") }
        return urls[index] as NSURL
    }

    @objc func previewPanel(_ panel: QLPreviewPanel, handle event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        switch event.keyCode {
        case 49, 53: // Espacio / Esc cierran
            panel.orderOut(nil)
            return true
        case 125: // ↓ — siguiente elemento
            previewPanelSource?.moveSelection(by: 1)
            panel.reloadData()
            return true
        case 126: // ↑ — anterior
            previewPanelSource?.moveSelection(by: -1)
            panel.reloadData()
            return true
        default:
            return false
        }
    }

    /// ¿Los modificadores del evento están exactamente en alguno de los conjuntos dados?
    private func flagsEither(_ sets: [NSEvent.ModifierFlags], _ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return sets.contains(flags)
    }

    private func pasteItemsFromClipboardToActivePanel() {
        let urls = clipboardFileURLs()
        guard !urls.isEmpty else {
            statusLabel.stringValue = "No hay rutas válidas en portapapeles para pegar."
            NSSound.beep()
            return
        }
        let destination = activePanel.currentDirectoryURL
        let pasteboard = NSPasteboard.general
        // v2.1.1 — si el portapapeles viene de un «Cortar», pegar MUEVE (y consume el corte).
        let isCut = pasteboard.data(forType: FilePanelViewController.cutPasteboardType) != nil
            || pasteboard.data(forType: FilePanelViewController.finderCutType) != nil
        if isCut {
            pasteboard.setData(nil, forType: FilePanelViewController.cutPasteboardType)
            pasteboard.setData(nil, forType: FilePanelViewController.finderCutType)
            enqueueFileJob(type: .move, selected: urls, destination: destination)
            statusLabel.stringValue = "Moviendo \(urls.count) elemento(s) a panel \(activeSide.rawValue)…"
            return
        }
        if shouldUseSystemCopy(sources: urls, destination: destination) {
            runSystemCopy(sources: urls, destination: destination)
            return
        }
        enqueueFileJob(type: .copy, selected: urls, destination: activePanel.currentDirectoryURL)
        statusLabel.stringValue = "Pegando \(urls.count) elemento(s) en panel \(activeSide.rawValue)..."
    }

    private func clipboardFileURLs() -> [URL] {
        let pasteboard = NSPasteboard.general
        // v2.1.1 — primero URLs de archivo reales (Finder, esta app); después rutas en texto.
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            let fm = FileManager.default
            return urls.filter { fm.fileExists(atPath: $0.path) }
        }
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else {
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
        statusLabel.stringValue = "Copiando \(sources.count) elemento(s) en mismo volumen con copia del sistema..."
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
        backHistoryMenu.delegate = self
        forwardHistoryMenu.delegate = self
        window.toolbar = toolbar
        toolbarConfigured = true
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        // v2.3.6 — «Diagnostics» sale del toolbar: es herramienta de soporte, no de uso
        // diario. Sigue disponible en el menú Operaciones, la paleta (⌘K) y el editor de
        // atajos; en su lugar van los indicadores de CPU/RAM/batería.
        [
            ToolbarID.back, ToolbarID.forward, ToolbarID.home, ToolbarID.panelMode, .flexibleSpace,
            ToolbarID.newTab, ToolbarID.copy, ToolbarID.move, ToolbarID.delete,
            ToolbarID.mkdir, ToolbarID.rename, ToolbarID.deletePermanent,
            .flexibleSpace, ToolbarID.refresh, .space,
            ToolbarID.tasks, .space, ToolbarID.search, .space, ToolbarID.monitor
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
            item.label = "Atrás"
            item.toolTip = "Volver (clic derecho: historial)"
            let backButton = NSButton(
                image: NSImage(systemSymbolName: "chevron.left", accessibilityDescription: nil) ?? NSImage(),
                target: self,
                action: #selector(goBack)
            )
            backButton.bezelStyle = .toolbar
            backButton.menu = backHistoryMenu
            backButton.setAccessibilityLabel("Atrás")
            item.view = backButton
        case ToolbarID.forward:
            item.label = "Adelante"
            item.toolTip = "Avanzar (clic derecho: historial)"
            let forwardButton = NSButton(
                image: NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil) ?? NSImage(),
                target: self,
                action: #selector(goForward)
            )
            forwardButton.bezelStyle = .toolbar
            forwardButton.menu = forwardHistoryMenu
            forwardButton.setAccessibilityLabel("Adelante")
            item.view = forwardButton
        case ToolbarID.home:
            item.label = "Inicio"
            item.toolTip = "Ir al Home del usuario"
            item.image = NSImage(systemSymbolName: "house", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(goHome)
        case ToolbarID.panelMode:
            item.label = singlePanelMode ? "Usar dos paneles" : "Usar un solo panel"
            item.toolTip = panelModeTooltip
            let panelModeButton = NSButton(
                image: NSImage(
                    systemSymbolName: panelModeSymbolName,
                    accessibilityDescription: "Alternar uno o dos paneles"
                ) ?? NSImage(),
                target: self,
                action: #selector(onToggleSinglePanelRequested)
            )
            panelModeButton.bezelStyle = .toolbar
            panelModeButton.toolTip = panelModeTooltip
            panelModeButton.setAccessibilityLabel("Alternar uno o dos paneles")
            item.view = panelModeButton
            panelModeToolbarItem = item
            panelModeToolbarButton = panelModeButton
        case ToolbarID.newTab:
            item.label = "Nueva pestaña"
            item.toolTip = "Nueva pestaña (⌘T)"
            item.image = NSImage(systemSymbolName: "plus.square.on.square", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(newTab)
        case ToolbarID.copy:
            item.label = "Copiar"
            item.toolTip = "Copiar al otro panel (F5)"
            item.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(copySelection)
        case ToolbarID.move:
            item.label = "Mover"
            item.toolTip = "Mover al otro panel (F6)"
            item.image = NSImage(systemSymbolName: "arrow.right.doc.on.clipboard", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(moveSelection)
        case ToolbarID.delete:
            item.label = "Papelera"
            item.toolTip = "Enviar a Papelera (F8)"
            item.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(deleteSelection)
        case ToolbarID.mkdir:
            item.label = "Nueva carpeta"
            item.toolTip = "Crear carpeta (F7)"
            item.image = NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(createDirectory)
        case ToolbarID.rename:
            item.label = "Renombrar"
            item.toolTip = "Renombrar item seleccionado"
            item.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(renameSelection)
        case ToolbarID.deletePermanent:
            item.label = "Eliminar"
            item.toolTip = "Eliminar definitivamente"
            item.image = NSImage(systemSymbolName: "trash.slash", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(deleteSelectionPermanently)
        case ToolbarID.tasks:
            item.label = "Tareas"
            item.toolTip = "Abrir Task Manager"
            item.image = NSImage(systemSymbolName: "list.bullet.rectangle", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(openTaskManager)
        case ToolbarID.refresh:
            item.label = "Refrescar"
            item.toolTip = "Refrescar panel activo"
            item.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(manualRefresh)
        case ToolbarID.monitor:
            // v2.3.6 — indicadores en vivo. El ítem es una vista; su ciclo de vida va
            // ligado a la ventana (arranca/para el timer en viewDidMoveToWindow).
            item.label = "Monitoreo"
            item.toolTip = "CPU, memoria y batería de esta Mac · clic para abrir Monitor de Actividad"
            item.visibilityPriority = .high
            item.view = systemMonitorView
        case ToolbarID.search:
            searchField.placeholderString = globalSearchScope ? "Buscar en todo el índice…" : "Buscar en esta carpeta…"
            searchField.toolTip = globalSearchScope
                ? "Búsqueda global: abarca todas las ubicaciones indexadas."
                : "Búsqueda en la carpeta actual. Pulsa ⌘F para buscar en todo el índice."
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

        let imageView: NSImageView
        let label: NSTextField
        if let existingLabel = cell.textField, let existingImage = cell.imageView {
            label = existingLabel
            imageView = existingImage
        } else {
            // v2.1.1 — filas con icono (aspecto de barra lateral nativa).
            imageView = NSImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            cell.imageView = imageView
            cell.addSubview(imageView)
            label = NSTextField(labelWithString: "")
            label.translatesAutoresizingMaskIntoConstraints = false
            label.font = .systemFont(ofSize: 12)
            label.lineBreakMode = .byTruncatingMiddle
            cell.textField = label
            cell.addSubview(label)
            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 16),
                imageView.heightAnchor.constraint(equalToConstant: 16),
                label.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }

        let url: URL?
        var symbolName = "clock"
        var tint = NSColor.secondaryLabelColor
        if tableView == authorizedTable {
            url = authorizedLocations[safe: row]
            symbolName = "folder.fill"
            tint = J4FDesign.brand
        } else if tableView == favoritesTable {
            url = favoriteLocations[safe: row]
            symbolName = "star.fill"
            tint = .systemYellow
        } else if tableView == reauthTable {
            symbolName = "exclamationmark.triangle.fill"
            tint = .systemOrange
            if let path = failedBookmarks[safe: row]?.path, !path.isEmpty {
                url = URL(fileURLWithPath: path)
            } else {
                url = nil
            }
        } else {
            url = recentLocations[safe: row]
        }

        let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
        imageView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(symbolConfiguration)
        imageView.contentTintColor = tint
        label.stringValue = url?.lastPathComponent.isEmpty == false ? (url?.lastPathComponent ?? "--") : (url?.path ?? "--")
        label.toolTip = url?.path
        return cell
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        switch item.itemIdentifier {
        case ToolbarID.back:
            return activePanel.canGoBack
        case ToolbarID.forward:
            return activePanel.canGoForward
        case ToolbarID.home:
            return true
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
        if let field = obj.object as? NSSearchField, field == searchField {
            activePanel.setSearchQuery(field.stringValue)
            return
        }
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

/// v2.3.6 — control de pestañas con clic derecho. `NSSegmentedControl` no expone menú
/// contextual propio, así que al pulsar con el botón derecho el control avisa a su panel
/// con el índice pulsado (calculado por geometría: los segmentos son de ancho uniforme)
/// y el evento, para que el panel sitúe el menú.
private final class J4FTabsSegmentedControl: NSSegmentedControl {
    var onRightClickSegment: ((Int, NSEvent) -> Void)?

    override func rightMouseDown(with event: NSEvent) {
        guard segmentCount > 0 else {
            super.rightMouseDown(with: event)
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        let segmentWidth = bounds.width / CGFloat(segmentCount)
        guard segmentWidth > 0 else { return }
        let rawIndex = Int(floor((point.x - bounds.minX) / segmentWidth))
        let index = max(0, min(segmentCount - 1, rawIndex))
        onRightClickSegment?(index, event)
    }
}

private final class FilePanelViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate, NSCollectionViewDataSource, NSCollectionViewDelegate, NSTextFieldDelegate {
    var onActivate: (() -> Void)?
    var onStatus: ((String) -> Void)?
    var onDirectoryChanged: ((URL) -> Void)?
    /// Ola 1 — cambios de selección (refresco del preview QuickLook).
    var onSelectionChanged: (() -> Void)?
    /// Ola 1 — drag & drop: (orígenes, destino, ¿copiar?).
    var onDropRequest: (([URL], URL, Bool) -> Void)?
    var onPasteRequested: (() -> Void)?
    var onSearchWillStart: (() -> Void)?
    var onSearchDidFinish: (() -> Void)?
    /// v2.0 — scope de búsqueda: true = todo el índice (⌘F); false = subárbol de la carpeta actual.
    var isGlobalSearchActive: (() -> Bool)?
    /// Raíces a asegurar antes de una búsqueda global (paneles + ubicaciones autorizadas).
    var indexRootsProvider: (() -> [URL])?
    // v2.1.1 — acciones de contexto que coordina el commander (otro panel, favoritos, sandbox).
    var onOpenInOtherPanel: ((URL) -> Void)?
    var onAddLocationRequested: ((URL?) -> Void)?
    var onToggleFavoriteRequested: ((URL) -> Void)?
    var isFavoriteProvider: ((URL) -> Bool)?
    var onQuickLookRequested: (() -> Void)?

    private let side: PanelSide
    private let tableView = FocusAwareTableView()
    private let rowCountLabel = NSTextField(labelWithString: "")
    private let tabsControl = J4FTabsSegmentedControl()
    private let indexedSearch = IndexedSearchService.shared
    private let flatToggleButton = NSButton()
    /// v2.0 — registro del panel (os_log) para fallos silenciosos (IA, índice…).
    private let logger = Logger(subsystem: "com.dmx83.just4folders", category: "panel")

    private var allRows: [FileRow] = []
    /// v1.2 — vista aplanada: cuando está activa, `flatRows` (índice) es la fuente.
    private var flatView = false
    private var flatRows: [FileRow] = []
    private var flatLoading = false
    private var pendingFlatRefreshWorkItem: DispatchWorkItem?
    private var rows: [FileRow] = []
    private var searchRows: [FileRow] = []
    private var loadTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var loadToken = UUID()
    private var searchToken = UUID()
    private var pendingRefreshWorkItem: DispatchWorkItem?
    private var pendingSearchWorkItem: DispatchWorkItem?
    private var tabURLs: [URL] = []
    private var activeTabIndex = 0
    /// Ola 2 — títulos personalizados por pestaña (nil = nombre de la carpeta).
    private var tabCustomTitles: [String?] = []
    private var rootSelected = false

    private var historyBack: [URL] = []
    private var historyForward: [URL] = []
    private(set) var currentURL: URL
    private var sortColumn: String = "name"
    private var ascending = true
    private var searchQuery: String = ""
    /// v1.2 — filtro rápido: teclea para filtrar la lista actual (⌫ borra, Esc limpia).
    private var quickFilter: String = ""
    /// v1.2 — caché de color de etiqueta Finder por ruta (0 = sin color).
    private let tagColorCache = NSCache<NSString, NSNumber>()
    /// v1.2 — carpetas cuyo tamaño se está calculando ya (evita peticiones repetidas).
    private var folderSizeRequests: Set<String> = []
    /// v2.0 — formatos por carpeta (aplanada/orden/ocultos, estilo Directory Opus).
    private let folderFormatStore = FolderFormatStore.shared
    private var isRestoringFormat = false
    private var didApplyInitialFormat = false
    /// Diseño (P2) — HUD transitorio del filtro rápido (patrón type-select).
    private let quickFilterHUD = NSVisualEffectView()
    private let quickFilterHUDLabel = NSTextField(labelWithString: "")
    private var quickFilterHUDHideWorkItem: DispatchWorkItem?
    /// Ola 1 — estado vacío / sin coincidencias.
    private let emptyStateLabel = NSTextField(labelWithString: "")
    /// Ola 1 — breadcrumb clicable.
    private let breadcrumbRow = NSStackView()
    private var breadcrumbURLs: [URL] = []
    // v2.1.1 — barra de dirección única: [◀ ▶] + ruta navegable (breadcrumb) o editable (campo).
    private let addressBackButton = NSButton()
    private let addressForwardButton = NSButton()
    private let addressPathContainer = NSView()
    private let pathEditField = NSTextField(string: "")
    private var isEditingAddress = false
    // v2.1.1 — anchos de columna ajustados a mano (se recuerdan por carpeta; sin refit agresivo).
    private var userAdjustedColumns = false
    private var isFittingColumns = false
    private var columnResizeSaveWorkItem: DispatchWorkItem?
    /// Ola 3 — hover por fila y submenú de workspaces.
    private var hoveredRow = -1
    private weak var contextMenu: NSMenu?
    /// v2.1.1 — etiquetas estables de los ítems del menú contextual (para habilitar/renombrar).
    private enum ContextTag: Int {
        case openInTab = 1, openInOther, openWith, quickLook, showInFinder, openTerminal
        case newFolder, rename, duplicate, compress
        case cut, copy, paste, trash, deletePermanent
        case copyPath, favorite, addLocation, info, tags, share, tools, workspaces, pict, pdf
    }
    private var hoverMonitor: Any?
    /// Ola 3 — galería: modo de vista, colección y scroll propios.
    private enum ViewMode: String { case list, gallery }
    private var viewMode: ViewMode = .list
    private let galleryScrollView = NSScrollView()
    private let collectionView = NSCollectionView()
    private let galleryLayout = NSCollectionViewFlowLayout()
    private weak var listScrollView: NSScrollView?
    /// Ola 3 — árbol del panel (columna colapsable a la izquierda).
    private let panelTreeScroll = NSScrollView()
    private let panelTreeView = NSOutlineView()
    private var treeController: PanelTreeController?
    private var treeWidthConstraint: NSLayoutConstraint?
    private var panelTreeVisible = UserDefaults.standard.bool(forKey: "j4f.panelTreeVisible")
    private var includeHiddenFiles = false
    private var isActivePanel = false

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

    deinit {
        loadTask?.cancel()
        searchTask?.cancel()
        pendingRefreshWorkItem?.cancel()
        pendingSearchWorkItem?.cancel()
        pendingFlatRefreshWorkItem?.cancel()
        quickFilterHUDHideWorkItem?.cancel()
        if let hoverMonitor {
            NSEvent.removeMonitor(hoverMonitor)
        }
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
        isActivePanel = isActive
        view.layer?.borderColor = isActive ? NSColor.controlAccentColor.cgColor : NSColor.separatorColor.cgColor
        view.layer?.borderWidth = isActive ? 2 : 1
    }

    func flashIndexReady() {
        guard let layer = view.layer else { return }
        layer.borderColor = NSColor.systemGreen.cgColor
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self else { return }
            self.setActive(self.isActivePanel)
        }
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
            onStatus?("Ruta inválida o no es carpeta: \(clean)")
            NSSound.beep()
            return
        }
        loadDirectory(url, pushHistory: true)
    }

    func openURL(_ url: URL) {
        let normalized = url.standardizedFileURL
        guard isDirectory(normalized) else {
            onStatus?("Ruta inválida o no es carpeta: \(url.path)")
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
        quickFilter = ""
        hideQuickFilterHUD()
        pendingSearchWorkItem?.cancel()
        searchTask?.cancel()

        guard !searchQuery.isEmpty else {
            searchRows.removeAll(keepingCapacity: true)
            applySortAndReload()
            onStatus?("\(rows.count) elemento(s) en \(currentURL.path)")
            return
        }

        let work = DispatchWorkItem { [weak self] in
            self?.startDeepSearch(query: self?.searchQuery ?? "")
        }
        pendingSearchWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
    }

    /// v2.0 — relanza la búsqueda actual sin debounce (p. ej. al cambiar el scope global con
    /// texto ya escrito, o al terminar de indexar tras una búsqueda global).
    func rerunSearchNow() {
        guard !searchQuery.isEmpty else { return }
        pendingSearchWorkItem?.cancel()
        searchTask?.cancel()
        startDeepSearch(query: searchQuery)
    }

    // MARK: - Filtro rápido (v1.2: escribir filtra la lista, ⌫ borra, Esc limpia)

    var hasQuickFilter: Bool { !quickFilter.isEmpty }

    /// ¿La tabla de este panel tiene el foco del teclado?
    func isTableFirstResponder() -> Bool {
        view.window?.firstResponder === tableView || view.window?.firstResponder === collectionView
    }

    func appendQuickFilter(_ text: String) {
        quickFilter += text
        activatePanel()
        applySortAndReload()
        onStatus?("Filtro: «\(quickFilter)» — \(rows.count) coincidencia(s) · Esc limpia")
        updateQuickFilterHUD()
    }

    func removeQuickFilterLastCharacter() {
        guard !quickFilter.isEmpty else { return }
        quickFilter.removeLast()
        applySortAndReload()
        if quickFilter.isEmpty {
            onStatus?("Filtro limpiado.")
            hideQuickFilterHUD()
        } else {
            onStatus?("Filtro: «\(quickFilter)» — \(rows.count) coincidencia(s) · Esc limpia")
            updateQuickFilterHUD()
        }
    }

    func clearQuickFilter() {
        guard !quickFilter.isEmpty else { return }
        quickFilter = ""
        applySortAndReload()
        onStatus?("Filtro limpiado.")
        hideQuickFilterHUD()
    }

    // MARK: - HUD del filtro rápido (P2 de diseño)

    private func updateQuickFilterHUD() {
        guard !quickFilter.isEmpty else {
            hideQuickFilterHUD()
            return
        }
        quickFilterHUDLabel.stringValue = "\(quickFilter)   ·   \(rows.count) coincidencia(s)"
        quickFilterHUD.isHidden = false
        quickFilterHUD.alphaValue = 1
        quickFilterHUDHideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.quickFilterHUD.animator().alphaValue = 0
        }
        quickFilterHUDHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
    }

    private func hideQuickFilterHUD() {
        quickFilterHUDHideWorkItem?.cancel()
        quickFilterHUDHideWorkItem = nil
        quickFilterHUD.isHidden = true
        quickFilterHUD.alphaValue = 0
    }

    // MARK: - Etiquetas Finder (v1.2: color por fila + toggle en menú contextual)

    nonisolated static let tagPalette: [(name: String, colorIndex: Int)] = [
        ("Rojo", 6), ("Naranja", 7), ("Amarillo", 5), ("Verde", 2),
        ("Azul", 4), ("Morado", 3), ("Gris", 1)
    ]

    nonisolated static func tagColor(forIndex index: Int) -> NSColor? {
        switch index {
        case 1: return .systemGray
        case 2: return .systemGreen
        case 3: return .systemPurple
        case 4: return .systemBlue
        case 5: return .systemYellow
        case 6: return .systemRed
        case 7: return .systemOrange
        default: return nil
        }
    }

    /// Índice de color de la primera etiqueta con color (0 = sin color). Cacheado por ruta.
    private func tagColorIndex(for url: URL) -> Int {
        let key = url.standardizedFileURL.path as NSString
        if let cached = tagColorCache.object(forKey: key) { return cached.intValue }
        let index = FinderTags.entries(of: url).first(where: { $0.colorIndex > 0 })?.colorIndex ?? 0
        tagColorCache.setObject(NSNumber(value: index), forKey: key)
        return index
    }

    private func invalidateTagColorCache(for urls: [URL]) {
        for url in urls {
            tagColorCache.removeObject(forKey: url.standardizedFileURL.path as NSString)
        }
    }

    @objc private func contextApplyTag(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        let colorIndex = Self.tagPalette.first(where: { $0.name == name })?.colorIndex ?? 0
        let urls = selectedURLs()
        guard !urls.isEmpty else { return }
        let allHave = urls.allSatisfy { url in
            FinderTags.entries(of: url).contains { $0.name == name }
        }
        let entry = FinderTags.TagEntry(name: name, colorIndex: colorIndex)
        var updated = 0
        for url in urls {
            let change = allHave ? FinderTags.remove([name], from: url) : FinderTags.addColored([entry], to: url)
            if change == .updated { updated += 1 }
        }
        invalidateTagColorCache(for: urls)
        tableView.reloadData()
        onStatus?("Etiqueta «\(name)» \(allHave ? "quitada" : "puesta") en \(updated) elemento(s).")
    }

    @objc private func contextClearTags() {
        let urls = selectedURLs()
        guard !urls.isEmpty else { return }
        var updated = 0
        for url in urls {
            let names = FinderTags.entries(of: url).map(\.name)
            guard !names.isEmpty else { continue }
            if FinderTags.remove(names, from: url) == .updated { updated += 1 }
        }
        invalidateTagColorCache(for: urls)
        tableView.reloadData()
        onStatus?("Etiquetas quitadas en \(updated) elemento(s).")
    }

    @objc private func contextBatchRename() {
        activatePanel()
        NotificationCenter.default.post(name: .j4fBatchRename, object: nil)
    }

    @objc private func contextFindDuplicates() {
        activatePanel()
        NotificationCenter.default.post(name: .j4fFindDuplicates, object: nil)
    }

    @objc private func contextOrderFolder() {
        activatePanel()
        NotificationCenter.default.post(name: .j4fOrderFolder, object: nil)
    }

    func selectedURLs() -> [URL] {
        if viewMode == .gallery {
            let indexes = collectionView.selectionIndexPaths.compactMap(\.item).sorted()
            let urls = indexes.compactMap { $0 < rows.count ? rows[$0].url : nil }
            if !urls.isEmpty { return urls }
            return rootSelected ? [currentURL] : []
        }
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
                onStatus?("No se pudo borrar \(url.lastPathComponent): \(J4FError.from(error).userMessage)")
            }
        }
        loadDirectory(currentURL, pushHistory: false)
        return deleted
    }

    func createDirectory(named name: String) throws {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw NSError(domain: "JUST4FOLDERS", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Nombre de carpeta vacío."]) }
        let target = currentURL.appendingPathComponent(clean, isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        loadDirectory(currentURL, pushHistory: false)
    }

    func renameSelected(to newName: String) throws {
        let selected = selectedURLs()
        guard selected.count == 1, let source = selected.first else {
            throw NSError(domain: "JUST4FOLDERS", code: 1002, userInfo: [NSLocalizedDescriptionKey: "Selecciona un único elemento para renombrar."])
        }
        try renameItem(at: source, to: newName)
    }

    func renameItem(at source: URL, to newName: String) throws {
        let clean = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            throw NSError(domain: "JUST4FOLDERS", code: 1003, userInfo: [NSLocalizedDescriptionKey: "Nuevo nombre vacío."])
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
                onStatus?("No se pudo eliminar \(url.lastPathComponent): \(J4FError.from(error).userMessage)")
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
        saveFormat()
        loadDirectory(currentURL, pushHistory: false)
    }

    /// Recarga tras cambios hechos por ventanas auxiliares (rename en lote, duplicados…).
    func reloadAfterExternalChange() {
        loadDirectory(currentURL, pushHistory: false)
    }

    func refreshForChangedPaths(_ changedPaths: [String]) {
        guard !changedPaths.isEmpty else { return }
        if flatView {
            // La fuente es el índice: re-consulta (con debounce) tras refrescar el índice.
            scheduleFlatViewRefresh()
            return
        }

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
            // v1.2 — un cambio dentro invalida el total cacheado de las carpetas afectadas.
            Task { await FolderSizeCalculator.shared.invalidate(path: childPath) }
            if var row = rowMap[childPath], row.isDirectory {
                row.folderSizeBytes = nil
                rowMap[childPath] = row
            }
        }

        allRows = Array(rowMap.values)
        applySortAndReload()
        onStatus?("Actualizado (\(childPaths.count) cambio(s) en disco).")
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
        let pasteboard = NSPasteboard.general
        var sources: [URL] = []
        // v2.1.1 — primero URLs de archivo (Finder y esta app); después rutas en texto.
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            sources = urls
        } else if let text = pasteboard.string(forType: .string), !text.isEmpty {
            sources = text
                .split(whereSeparator: \.isNewline)
                .compactMap { line in
                    let value = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !value.isEmpty else { return nil }
                    return URL(fileURLWithPath: value)
                }
        }

        guard !sources.isEmpty else { return 0 }

        let isCut = pasteboard.data(forType: Self.cutPasteboardType) != nil
            || pasteboard.data(forType: Self.finderCutType) != nil

        let fm = FileManager.default
        var pasted = 0
        for source in sources {
            let normalized = source.standardizedFileURL
            guard fm.fileExists(atPath: normalized.path) else { continue }
            let proposed = currentURL.appendingPathComponent(normalized.lastPathComponent, isDirectory: isDirectory(normalized))
            let destination = availableDestination(for: proposed)
            do {
                if isCut {
                    try fm.moveItem(at: normalized, to: destination)
                } else {
                    try fm.copyItem(at: normalized, to: destination)
                }
                pasted += 1
            } catch {
                onStatus?("Error pegando \(normalized.lastPathComponent): \(J4FError.from(error).userMessage)")
            }
        }

        if pasted > 0 {
            if isCut {
                // El corte se consume con el primer pegado (como en Finder).
                pasteboard.setData(nil, forType: Self.cutPasteboardType)
                pasteboard.setData(nil, forType: Self.finderCutType)
            }
            loadDirectory(currentURL, pushHistory: false)
        }
        return pasted
    }

    func newTab() {
        tabURLs.append(currentURL)
        tabCustomTitles.append(nil)
        activeTabIndex = tabURLs.count - 1
        historyBack.removeAll()
        historyForward.removeAll()
        refreshTabsControl()
        loadDirectory(currentURL, pushHistory: false)
    }

    // MARK: - Pestañas completas (Ola 2)

    /// v2.3.6 — cierra la pestaña `index` (clic derecho incluido). Solo recarga el
    /// directorio si la pestaña cerrada era la activa.
    @discardableResult
    func closeTab(at index: Int) -> Bool {
        guard tabURLs.count > 1, tabURLs.indices.contains(index) else { return false }
        let wasActive = index == activeTabIndex
        tabURLs.remove(at: index)
        if index < tabCustomTitles.count {
            tabCustomTitles.remove(at: index)
        }
        if wasActive {
            if activeTabIndex >= tabURLs.count {
                activeTabIndex = max(0, tabURLs.count - 1)
            }
            historyBack.removeAll()
            historyForward.removeAll()
            refreshTabsControl()
            loadDirectory(tabURLs[activeTabIndex], pushHistory: false)
        } else {
            if index < activeTabIndex {
                activeTabIndex -= 1
            }
            refreshTabsControl()
        }
        return true
    }

    @discardableResult
    func closeCurrentTab() -> Bool {
        closeTab(at: activeTabIndex)
    }

    /// v2.3.6 — cierra todas las pestañas salvo `index` (clic derecho, «Cerrar las demás»).
    func closeOtherTabs(keeping index: Int) {
        guard tabURLs.count > 1, tabURLs.indices.contains(index) else { return }
        let url = tabURLs[index]
        let custom = index < tabCustomTitles.count ? tabCustomTitles[index] : nil
        tabURLs = [url]
        tabCustomTitles = [custom]
        activeTabIndex = 0
        historyBack.removeAll()
        historyForward.removeAll()
        refreshTabsControl()
        loadDirectory(url, pushHistory: false)
    }

    func tabTitle(at index: Int) -> String {
        guard tabURLs.indices.contains(index) else { return "" }
        let url = tabURLs[index]
        let base = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        let custom = index < tabCustomTitles.count ? tabCustomTitles[index] : nil
        return custom ?? base
    }

    func currentTabTitle() -> String {
        tabTitle(at: activeTabIndex)
    }

    /// Duplica la pestaña `index` (misma carpeta e historial limpio).
    func duplicateTab(at index: Int) {
        guard tabURLs.indices.contains(index) else { return }
        let url = tabURLs[index]
        let custom = index < tabCustomTitles.count ? tabCustomTitles[index] : nil
        let insertAt = index + 1
        tabURLs.insert(url, at: insertAt)
        tabCustomTitles.insert(custom, at: min(insertAt, tabCustomTitles.count))
        activeTabIndex = insertAt
        historyBack.removeAll()
        historyForward.removeAll()
        refreshTabsControl()
        loadDirectory(url, pushHistory: false)
    }

    /// Duplica la pestaña actual (misma carpeta e historial limpio).
    func duplicateCurrentTab() {
        duplicateTab(at: activeTabIndex)
    }

    /// Renombra la pestaña `index` (cadena vacía = volver al nombre de la carpeta).
    func renameTab(at index: Int, as name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard index < tabCustomTitles.count else { return }
        tabCustomTitles[index] = clean.isEmpty ? nil : clean
        refreshTabsControl()
    }

    /// Renombra la pestaña actual (cadena vacía = volver al nombre de la carpeta).
    func renameCurrentTab(as name: String) {
        renameTab(at: activeTabIndex, as: name)
    }

    /// v2.3.6 — diálogo «Renombrar pestaña» sobre cualquier índice: lo comparten el
    /// atajo ⌥⌘R (pestaña activa) y el menú del clic derecho.
    func promptRenameTab(at index: Int) {
        guard tabURLs.indices.contains(index) else { return }
        let alert = NSAlert()
        alert.messageText = "Renombrar pestaña"
        alert.informativeText = "Deja el campo vacío para volver al nombre de la carpeta."
        alert.addButton(withTitle: "Renombrar")
        alert.addButton(withTitle: "Cancelar")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = tabTitle(at: index)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        renameTab(at: index, as: field.stringValue)
        onStatus?("Pestaña renombrada.")
    }

    func promptRenameActiveTab() {
        promptRenameTab(at: activeTabIndex)
    }

    /// Mueve la pestaña `index` una posición (izquierda = -1).
    func moveTab(at index: Int, by delta: Int) {
        let target = index + delta
        guard tabURLs.indices.contains(index), tabURLs.indices.contains(target) else { return }
        tabURLs.swapAt(index, target)
        if index < tabCustomTitles.count, target < tabCustomTitles.count {
            tabCustomTitles.swapAt(index, target)
        }
        if activeTabIndex == index {
            activeTabIndex = target
        } else if activeTabIndex == target {
            activeTabIndex = index
        }
        refreshTabsControl()
    }

    /// Mueve la pestaña actual una posición (izquierda = -1).
    func moveCurrentTab(by delta: Int) {
        moveTab(at: activeTabIndex, by: delta)
    }

    // MARK: - Menú contextual de pestañas (v2.3.6)

    /// Clic derecho sobre una pestaña: las acciones operan sobre esa pestaña concreta,
    /// sin cambiar la activa (como el menú de pestañas de Safari).
    private func showTabContextMenu(forTabAt index: Int, event: NSEvent) {
        guard tabURLs.indices.contains(index) else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false

        let close = NSMenuItem(title: "Cerrar pestaña", action: #selector(tabMenuClose(_:)), keyEquivalent: "")
        close.target = self
        close.representedObject = index
        close.isEnabled = tabURLs.count > 1
        menu.addItem(close)

        let closeOthers = NSMenuItem(title: "Cerrar las demás", action: #selector(tabMenuCloseOthers(_:)), keyEquivalent: "")
        closeOthers.target = self
        closeOthers.representedObject = index
        closeOthers.isEnabled = tabURLs.count > 1
        menu.addItem(closeOthers)

        menu.addItem(.separator())

        let duplicate = NSMenuItem(title: "Duplicar pestaña", action: #selector(tabMenuDuplicate(_:)), keyEquivalent: "")
        duplicate.target = self
        duplicate.representedObject = index
        menu.addItem(duplicate)

        let rename = NSMenuItem(title: "Renombrar pestaña…", action: #selector(tabMenuRename(_:)), keyEquivalent: "")
        rename.target = self
        rename.representedObject = index
        menu.addItem(rename)

        menu.addItem(.separator())

        let moveLeft = NSMenuItem(title: "Mover a la izquierda", action: #selector(tabMenuMoveLeft(_:)), keyEquivalent: "")
        moveLeft.target = self
        moveLeft.representedObject = index
        moveLeft.isEnabled = index > 0
        menu.addItem(moveLeft)

        let moveRight = NSMenuItem(title: "Mover a la derecha", action: #selector(tabMenuMoveRight(_:)), keyEquivalent: "")
        moveRight.target = self
        moveRight.representedObject = index
        moveRight.isEnabled = index < tabURLs.count - 1
        menu.addItem(moveRight)

        NSMenu.popUpContextMenu(menu, with: event, for: tabsControl)
    }

    @objc private func tabMenuClose(_ sender: NSMenuItem) {
        guard let index = sender.representedObject as? Int else { return }
        _ = closeTab(at: index)
    }

    @objc private func tabMenuCloseOthers(_ sender: NSMenuItem) {
        guard let index = sender.representedObject as? Int else { return }
        closeOtherTabs(keeping: index)
        onStatus?("Cerradas las demás pestañas; queda «\(tabTitle(at: activeTabIndex))».")
    }

    @objc private func tabMenuDuplicate(_ sender: NSMenuItem) {
        guard let index = sender.representedObject as? Int else { return }
        duplicateTab(at: index)
        onStatus?("Pestaña duplicada.")
    }

    @objc private func tabMenuRename(_ sender: NSMenuItem) {
        guard let index = sender.representedObject as? Int else { return }
        promptRenameTab(at: index)
    }

    @objc private func tabMenuMoveLeft(_ sender: NSMenuItem) {
        guard let index = sender.representedObject as? Int else { return }
        moveTab(at: index, by: -1)
    }

    @objc private func tabMenuMoveRight(_ sender: NSMenuItem) {
        guard let index = sender.representedObject as? Int else { return }
        moveTab(at: index, by: 1)
    }

    // MARK: - Workspaces (Ola 3)

    func workspaceSnapshot() -> PanelWorkspace {
        PanelWorkspace(
            tabs: tabURLs.map { $0.standardizedFileURL.path },
            activeIndex: max(0, min(activeTabIndex, tabURLs.count - 1))
        )
    }

    func restoreWorkspace(_ snapshot: PanelWorkspace) {
        let urls = snapshot.tabs.map { URL(fileURLWithPath: $0, isDirectory: true) }
        guard !urls.isEmpty else { return }
        tabURLs = urls
        tabCustomTitles = Array(repeating: nil, count: urls.count)
        activeTabIndex = max(0, min(snapshot.activeIndex, urls.count - 1))
        historyBack.removeAll()
        historyForward.removeAll()
        refreshTabsControl()
        loadDirectory(urls[activeTabIndex], pushHistory: false)
    }

    // MARK: - Galería (Ola 3)

    var isGalleryMode: Bool { viewMode == .gallery }

    /// Alterna lista/galería (se recuerda por carpeta en el formato).
    func setGalleryMode(_ enabled: Bool) {
        applyGalleryMode(enabled)
        saveFormat()
        onStatus?(enabled ? "Vista en galería." : "Vista en lista.")
    }

    /// Aplica el modo sin guardar (restauración de formato).
    private func applyGalleryMode(_ enabled: Bool) {
        viewMode = enabled ? .gallery : .list
        galleryScrollView.isHidden = !enabled
        listScrollView?.isHidden = enabled
        if enabled {
            collectionView.reloadData()
        } else {
            tableView.reloadData()
        }
    }

    @objc private func galleryDoubleClick(_ sender: NSClickGestureRecognizer) {
        let point = sender.location(in: collectionView)
        guard let indexPath = collectionView.indexPathForItem(at: point) else { return }
        collectionView.deselectAll(nil)
        collectionView.selectItems(at: [indexPath], scrollPosition: [])
        openSelected()
    }

    func numberOfSections(in collectionView: NSCollectionView) -> Int { 1 }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        rows.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: GalleryItem.identifier, for: indexPath)
        if let galleryItem = item as? GalleryItem, indexPath.item < rows.count {
            galleryItem.configure(with: rows[indexPath.item])
        }
        return item
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        activatePanel()
        onSelectionChanged?()
    }

    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        onSelectionChanged?()
    }

    // MARK: - Historial con menú (Ola 2)

    func backHistoryURLs() -> [URL] {
        Array(historyBack.reversed())
    }

    func forwardHistoryURLs() -> [URL] {
        Array(historyForward.reversed())
    }

    /// Salta a una entrada del historial hacia atrás (rebobina el resto al historial adelante).
    func jumpBack(to url: URL) {
        guard let index = historyBack.lastIndex(where: { $0.standardizedFileURL == url.standardizedFileURL }) else { return }
        let skipped = Array(historyBack[(index + 1)...])
        historyBack.removeSubrange(index...)
        historyForward.append(contentsOf: skipped.reversed())
        loadDirectory(url, pushHistory: false)
    }

    /// Salta a una entrada del historial hacia adelante.
    func jumpForward(to url: URL) {
        guard let index = historyForward.lastIndex(where: { $0.standardizedFileURL == url.standardizedFileURL }) else { return }
        let skipped = Array(historyForward[(index + 1)...])
        historyForward.removeSubrange(index...)
        historyBack.append(contentsOf: skipped.reversed())
        loadDirectory(url, pushHistory: false)
    }

    private func configureUI() {
        view.wantsLayer = true
        view.layer?.cornerRadius = 8
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor.separatorColor.cgColor
        view.translatesAutoresizingMaskIntoConstraints = false

        rowCountLabel.font = J4FDesign.microFont()
        rowCountLabel.textColor = .tertiaryLabelColor

        tabsControl.segmentStyle = .capsule
        tabsControl.target = self
        tabsControl.action = #selector(tabSelectionChanged)
        tabsControl.setAccessibilityLabel("Pestanas del panel \(side.rawValue)")
        tabsControl.toolTip = "Clic: subir al directorio padre · Clic derecho: cerrar, duplicar, renombrar, mover"
        // v2.3.6 — clic derecho sobre una pestaña: menú de acciones de tab (incluye cerrar).
        tabsControl.onRightClickSegment = { [weak self] index, event in
            self?.showTabContextMenu(forTabAt: index, event: event)
        }
        refreshTabsControl()

        tableView.focusDelegate = self
        tableView.onEnterPressed = { [weak self] in
            self?.openSelected()
        }
        tableView.onBackgroundClicked = { [weak self] in
            self?.selectRootDirectory()
        }
        // v2.1.1 — altura explícita: un NSTableHeaderView con frame cero se queda en 0pt y la
        // cabecera no se ve (el usuario no puede descubrir las columnas ni redimensionarlas).
        let header = J4FFittingHeaderView(frame: NSRect(x: 0, y: 0, width: 100, height: 24))
        header.ownerPanel = self
        tableView.headerView = header
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.style = .inset
        tableView.rowHeight = 22
        tableView.allowsMultipleSelection = true
        tableView.allowsEmptySelection = true
        tableView.delegate = self
        tableView.dataSource = self
        tableView.doubleAction = #selector(openSelected)
        tableView.target = self
        let panelMenu = makeContextMenu()
        tableView.menu = panelMenu
        tableView.setAccessibilityLabel("Contenido del panel \(side.rawValue)")
        // Ola 1 — drag & drop: interior mueve (⌥ copia), desde fuera copia (⌘ mueve).
        tableView.registerForDraggedTypes([.fileURL])
        tableView.setDraggingSourceOperationMask([.move, .copy], forLocal: true)
        tableView.setDraggingSourceOperationMask([.copy], forLocal: false)
        // Ola 3 — hover por fila (monitor local; se retira en deinit).
        hoverMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .mouseExited]) { [weak self] event in
            self?.handleHoverEvent(event)
            return event
        }

        addColumn(id: "name", title: "Nombre", width: 180)
        addColumn(id: "size", title: "Tamaño", width: 65)
        addColumn(id: "modified", title: "Modificado", width: 100)
        addColumn(id: "type", title: "Tipo", width: 80)
        // v2.1.1 — el reparto lo hace fitColumnsToWidth (contra el viewport real y respetando
        // los anchos manuales del usuario); AppKit no debe tocar los anchos por su cuenta.
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        configureColumnMenu()

        tableView.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        listScrollView = scrollView

        // Ola 3 — galería (misma región; se muestra/oculta según el modo).
        galleryLayout.itemSize = NSSize(width: 108, height: 98)
        galleryLayout.minimumInteritemSpacing = 10
        galleryLayout.minimumLineSpacing = 10
        galleryLayout.sectionInset = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        collectionView.collectionViewLayout = galleryLayout
        setGalleryThumbSize(galleryThumbSizeKey)
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.backgroundColors = [.clear]
        collectionView.register(GalleryItem.self, forItemWithIdentifier: GalleryItem.identifier)
        collectionView.menu = panelMenu
        collectionView.setAccessibilityLabel("Galería del panel \(side.rawValue)")
        let galleryDoubleClick = NSClickGestureRecognizer(target: self, action: #selector(galleryDoubleClick(_:)))
        galleryDoubleClick.numberOfClicksRequired = 2
        collectionView.addGestureRecognizer(galleryDoubleClick)
        galleryScrollView.documentView = collectionView
        galleryScrollView.hasVerticalScroller = true
        galleryScrollView.translatesAutoresizingMaskIntoConstraints = false
        galleryScrollView.isHidden = true

        // v2.1.1 — barra de dirección: atrás/adelante + ruta navegable y editable + contador.
        addressBackButton.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: nil)
        addressBackButton.bezelStyle = .inline
        addressBackButton.controlSize = .small
        addressBackButton.target = self
        addressBackButton.action = #selector(addressBackPressed)
        addressBackButton.toolTip = "Atrás"
        addressBackButton.setAccessibilityLabel("Atrás")
        addressForwardButton.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
        addressForwardButton.bezelStyle = .inline
        addressForwardButton.controlSize = .small
        addressForwardButton.target = self
        addressForwardButton.action = #selector(addressForwardPressed)
        addressForwardButton.toolTip = "Adelante"
        addressForwardButton.setAccessibilityLabel("Adelante")
        addressBackButton.widthAnchor.constraint(equalToConstant: 22).isActive = true
        addressForwardButton.widthAnchor.constraint(equalToConstant: 22).isActive = true

        rowCountLabel.font = J4FDesign.microFont()
        rowCountLabel.textColor = .tertiaryLabelColor
        rowCountLabel.setContentHuggingPriority(.required, for: .horizontal)
        rowCountLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        pathEditField.font = .systemFont(ofSize: 11)
        pathEditField.controlSize = .small
        pathEditField.isHidden = true
        // v2.1.1 — OJO: sin esto el campo conserva AUTORESIZING (w==8) y choca con los pins
        // (los 20 «Unable to simultaneously satisfy» de la barra de dirección venían de aquí).
        pathEditField.translatesAutoresizingMaskIntoConstraints = false
        pathEditField.delegate = self
        pathEditField.target = self
        pathEditField.action = #selector(commitPathEditing)
        pathEditField.lineBreakMode = .byTruncatingMiddle
        pathEditField.setAccessibilityLabel("Editar dirección (Enter para ir, Esc para cancelar)")

        addressPathContainer.translatesAutoresizingMaskIntoConstraints = false
        addressPathContainer.addSubview(breadcrumbRow)
        addressPathContainer.addSubview(pathEditField)
        addressPathContainer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        addressPathContainer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let addressDoubleClick = NSClickGestureRecognizer(target: self, action: #selector(addressDoubleClicked))
        addressDoubleClick.numberOfClicksRequired = 2
        addressPathContainer.addGestureRecognizer(addressDoubleClick)

        let addressRow = NSStackView(views: [addressBackButton, addressForwardButton, addressPathContainer, rowCountLabel])
        addressRow.orientation = .horizontal
        addressRow.spacing = 6
        addressRow.alignment = .centerY
        addressRow.distribution = .fill
        addressRow.translatesAutoresizingMaskIntoConstraints = false
        addressPathContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true

        let tabsRow = NSStackView()
        tabsRow.orientation = .horizontal
        tabsRow.spacing = 8
        tabsRow.translatesAutoresizingMaskIntoConstraints = false
        tabsRow.addArrangedSubview(tabsControl)
        tabsRow.addArrangedSubview(NSView())
        breadcrumbRow.orientation = .horizontal
        breadcrumbRow.spacing = 2
        breadcrumbRow.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            breadcrumbRow.leadingAnchor.constraint(equalTo: addressPathContainer.leadingAnchor),
            breadcrumbRow.trailingAnchor.constraint(equalTo: addressPathContainer.trailingAnchor),
            breadcrumbRow.centerYAnchor.constraint(equalTo: addressPathContainer.centerYAnchor),
            pathEditField.leadingAnchor.constraint(equalTo: addressPathContainer.leadingAnchor),
            pathEditField.trailingAnchor.constraint(equalTo: addressPathContainer.trailingAnchor),
            pathEditField.centerYAnchor.constraint(equalTo: addressPathContainer.centerYAnchor),
            addressPathContainer.heightAnchor.constraint(equalToConstant: 22)
        ])
        // v2.1 — toggle plano con icono (antes checkbox genérico).
        flatToggleButton.setButtonType(.toggle)
        flatToggleButton.bezelStyle = .inline
        flatToggleButton.title = "Aplanada"
        flatToggleButton.image = NSImage(systemSymbolName: "rectangle.expand.vertical", accessibilityDescription: nil)
        flatToggleButton.imagePosition = .imageLeading
        flatToggleButton.contentTintColor = .secondaryLabelColor
        flatToggleButton.font = .systemFont(ofSize: 11)
        flatToggleButton.controlSize = .small
        flatToggleButton.target = self
        flatToggleButton.action = #selector(toggleFlatViewAction)
        flatToggleButton.toolTip = "Vista aplanada: todos los ficheros del subárbol (vía índice, sin recorrer carpetas)"
        flatToggleButton.setAccessibilityLabel("Vista aplanada del panel \(side.rawValue)")
        tabsRow.addArrangedSubview(flatToggleButton)

        let panelColumn = NSView()
        panelColumn.translatesAutoresizingMaskIntoConstraints = false
        panelColumn.addSubview(addressRow)
        panelColumn.addSubview(tabsRow)
        panelColumn.addSubview(scrollView)
        panelColumn.addSubview(galleryScrollView)

        // Ola 3 — árbol de carpetas del panel (columna colapsable, perezosa).
        let tree = PanelTreeController(root: FileManager.default.homeDirectoryForCurrentUser)
        tree.panel = self
        tree.outlineView = panelTreeView
        treeController = tree
        panelTreeView.headerView = nil
        panelTreeView.rowSizeStyle = .small
        panelTreeView.selectionHighlightStyle = .regular
        panelTreeView.dataSource = tree
        panelTreeView.delegate = tree
        panelTreeView.target = tree
        panelTreeView.doubleAction = #selector(PanelTreeController.treeDoubleClicked(_:))
        panelTreeView.setAccessibilityLabel("Árbol del panel \(side.rawValue)")
        if panelTreeView.tableColumns.isEmpty {
            let treeColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("panelTree"))
            treeColumn.title = "Carpetas"
            treeColumn.width = 160
            panelTreeView.addTableColumn(treeColumn)
            panelTreeView.outlineTableColumn = treeColumn
        }
        panelTreeScroll.documentView = panelTreeView
        panelTreeScroll.hasVerticalScroller = true
        panelTreeScroll.borderType = .noBorder
        panelTreeScroll.translatesAutoresizingMaskIntoConstraints = false
        panelTreeScroll.isHidden = !panelTreeVisible

        view.addSubview(panelTreeScroll)
        view.addSubview(panelColumn)

        configureQuickFilterHUD(above: scrollView)
        configureEmptyState(over: scrollView)

        NSLayoutConstraint.activate([
            addressRow.leadingAnchor.constraint(equalTo: panelColumn.leadingAnchor),
            addressRow.trailingAnchor.constraint(equalTo: panelColumn.trailingAnchor),
            addressRow.topAnchor.constraint(equalTo: panelColumn.topAnchor, constant: 6),
            tabsRow.leadingAnchor.constraint(equalTo: panelColumn.leadingAnchor),
            tabsRow.trailingAnchor.constraint(equalTo: panelColumn.trailingAnchor),
            tabsRow.topAnchor.constraint(equalTo: addressRow.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: panelColumn.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: panelColumn.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: tabsRow.bottomAnchor, constant: 8),
            scrollView.bottomAnchor.constraint(equalTo: panelColumn.bottomAnchor, constant: -8),
            galleryScrollView.leadingAnchor.constraint(equalTo: panelColumn.leadingAnchor),
            galleryScrollView.trailingAnchor.constraint(equalTo: panelColumn.trailingAnchor),
            galleryScrollView.topAnchor.constraint(equalTo: tabsRow.bottomAnchor, constant: 8),
            galleryScrollView.bottomAnchor.constraint(equalTo: panelColumn.bottomAnchor, constant: -8),

            panelTreeScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            panelTreeScroll.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            panelTreeScroll.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
            panelColumn.leadingAnchor.constraint(equalTo: panelTreeScroll.trailingAnchor, constant: 6),
            panelColumn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            panelColumn.topAnchor.constraint(equalTo: view.topAnchor),
            panelColumn.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        treeWidthConstraint = panelTreeScroll.widthAnchor.constraint(equalToConstant: panelTreeVisible ? 170 : 0)
        treeWidthConstraint?.isActive = true
    }

    /// Ola 3 — muestra/oculta el árbol lateral del panel (se recuerda entre sesiones).
    func setPanelTreeVisible(_ visible: Bool) {
        panelTreeVisible = visible
        panelTreeScroll.isHidden = !visible
        treeWidthConstraint?.constant = visible ? 170 : 0
        UserDefaults.standard.set(visible, forKey: "j4f.panelTreeVisible")
        onStatus?(visible ? "Árbol del panel visible." : "Árbol del panel oculto.")
        // v2.1 — al cambiar el ancho disponible, reparte las columnas para que no queden cortadas.
        DispatchQueue.main.async { [weak self] in self?.fitColumnsIfNeeded() }
    }

    var isPanelTreeVisible: Bool { panelTreeVisible }

    /// v2.0 — búsqueda semántica: expansión de la consulta con IA (si hay clave configurada).
    private let semanticExpander: (any QueryExpanding)? = DeepSeekQueryExpander()
    private var semanticSearchEnabled = UserDefaults.standard.bool(forKey: "j4f.semanticSearch")

    var isSemanticSearchEnabled: Bool { semanticSearchEnabled }
    var isSemanticSearchAvailable: Bool { semanticExpander != nil }

    func setSemanticSearch(_ enabled: Bool) {
        semanticSearchEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "j4f.semanticSearch")
    }

    /// v2.0 — tamaño de miniaturas de la galería (S/M/L), recordado entre sesiones.
    static let galleryThumbSizes: [String: CGFloat] = ["S": 88, "M": 124, "L": 176]

    func setGalleryThumbSize(_ key: String) {
        let size = Self.galleryThumbSizes[key] ?? Self.galleryThumbSizes["M"]!
        galleryLayout.itemSize = NSSize(width: size, height: size * 0.9)
        UserDefaults.standard.set(key, forKey: "j4f.galleryThumbSize")
    }

    var galleryThumbSizeKey: String { UserDefaults.standard.string(forKey: "j4f.galleryThumbSize") ?? "M" }

    @objc private func navigateToParentDirectory() {
        let parent = currentURL.deletingLastPathComponent()
        guard parent.path != currentURL.path else { return }
        openURL(parent)
    }

    private func configureQuickFilterHUD(above scrollView: NSScrollView) {
        quickFilterHUD.translatesAutoresizingMaskIntoConstraints = false
        quickFilterHUD.material = .hudWindow
        quickFilterHUD.blendingMode = .withinWindow
        quickFilterHUD.state = .active
        quickFilterHUD.wantsLayer = true
        quickFilterHUD.layer?.cornerRadius = 8
        quickFilterHUD.isHidden = true
        quickFilterHUD.alphaValue = 0
        quickFilterHUD.setAccessibilityLabel("Filtro rápido")

        quickFilterHUDLabel.translatesAutoresizingMaskIntoConstraints = false
        quickFilterHUDLabel.font = .systemFont(ofSize: 12, weight: .medium)
        quickFilterHUDLabel.textColor = .white
        quickFilterHUD.addSubview(quickFilterHUDLabel)
        view.addSubview(quickFilterHUD)

        NSLayoutConstraint.activate([
            quickFilterHUD.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            quickFilterHUD.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 12),
            quickFilterHUDLabel.leadingAnchor.constraint(equalTo: quickFilterHUD.leadingAnchor, constant: 10),
            quickFilterHUDLabel.trailingAnchor.constraint(equalTo: quickFilterHUD.trailingAnchor, constant: -10),
            quickFilterHUDLabel.topAnchor.constraint(equalTo: quickFilterHUD.topAnchor, constant: 6),
            quickFilterHUDLabel.bottomAnchor.constraint(equalTo: quickFilterHUD.bottomAnchor, constant: -6)
        ])
    }

    private func configureEmptyState(over scrollView: NSScrollView) {
        emptyStateLabel.font = .systemFont(ofSize: 12)
        emptyStateLabel.textColor = .tertiaryLabelColor
        emptyStateLabel.alignment = .center
        emptyStateLabel.lineBreakMode = .byWordWrapping
        emptyStateLabel.maximumNumberOfLines = 0
        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyStateLabel.isHidden = true
        view.addSubview(emptyStateLabel)
        NSLayoutConstraint.activate([
            emptyStateLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            emptyStateLabel.leadingAnchor.constraint(greaterThanOrEqualTo: scrollView.leadingAnchor, constant: 12),
            emptyStateLabel.trailingAnchor.constraint(lessThanOrEqualTo: scrollView.trailingAnchor, constant: -12)
        ])
    }

    /// Ola 1 — mensaje según el motivo: filtro activo o carpeta vacía de verdad.
    private func updateEmptyState() {
        let filtered = !quickFilter.isEmpty || !searchQuery.isEmpty
        emptyStateLabel.stringValue = filtered
            ? "Sin coincidencias\nPrueba otro filtro o pulsa Esc"
            : "Carpeta vacía\n⌘N para crear una carpeta"
        emptyStateLabel.isHidden = !rows.isEmpty
    }

    /// Ola 1 — recarga una celda concreta (p. ej. cuando llega una miniatura).
    private func reloadRow(forPath path: String, columnID: String) {
        guard let index = rows.firstIndex(where: { $0.url.standardizedFileURL.path == path }) else { return }
        guard let column = tableView.tableColumns.firstIndex(where: { $0.identifier.rawValue == columnID }) else { return }
        tableView.reloadData(forRowIndexes: IndexSet(integer: index), columnIndexes: IndexSet(integer: column))
    }

    /// v2.1.1 — menú contextual estilo Finder+: abrir/abrir con/compartir, operaciones de archivo,
    /// portapapeles real y las acciones que antes vivían en botones sueltos (favoritos/ubicaciones).
    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu(title: "Acciones")
        menu.delegate = self
        // El habilitado/renombrado se controla a mano en menuNeedsUpdate (no autoenable).
        menu.autoenablesItems = false
        contextMenu = menu

        func add(_ title: String, _ action: Selector, tag: ContextTag? = nil) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            if let tag {
                item.tag = tag.rawValue
            }
            menu.addItem(item)
        }

        add("Abrir", #selector(openSelected))
        add("Abrir en pestaña nueva", #selector(contextOpenInNewTab), tag: .openInTab)
        add("Abrir en el panel \(side == .left ? "derecho" : "izquierdo")", #selector(contextOpenInOtherPanel), tag: .openInOther)
        let openWithItem = NSMenuItem(title: "Abrir con", action: nil, keyEquivalent: "")
        openWithItem.tag = ContextTag.openWith.rawValue
        menu.addItem(openWithItem)
        menu.addItem(.separator())
        add("Ver (QuickLook)", #selector(contextQuickLook), tag: .quickLook)
        add("Mostrar en Finder", #selector(contextOpenInFinder), tag: .showInFinder)
        add("Abrir en Terminal", #selector(contextOpenInTerminal), tag: .openTerminal)
        menu.addItem(.separator())
        add("Nueva carpeta", #selector(contextCreateFolder), tag: .newFolder)
        add("Renombrar", #selector(contextRename), tag: .rename)
        add("Duplicar", #selector(contextDuplicateSelection), tag: .duplicate)
        add("Comprimir", #selector(contextCompressSelection), tag: .compress)
        // v2.3.3 — acciones rapidas de imagen (sips; fichero NUEVO) desde el clic derecho.
        // «Editar/Mejorar con JUST4PICT» se sumara cuando la app acepte ficheros (documentos o CLI).
        let pictItem = NSMenuItem(title: "JUST4PICT", action: nil, keyEquivalent: "")
        pictItem.tag = ContextTag.pict.rawValue
        let pictMenu = NSMenu(title: "JUST4PICT")
        let pictEntries: [(String, Int)] = [
            ("Convertir a PNG", 0),
            ("Convertir a JPEG", 1),
            ("Redimensionar 50 %", 2)
        ]
        for entry in pictEntries {
            let item = NSMenuItem(title: entry.0, action: #selector(contextPictQuickAction(_:)), keyEquivalent: "")
            item.target = self
            item.tag = entry.1
            pictMenu.addItem(item)
        }
        pictItem.submenu = pictMenu
        menu.addItem(pictItem)
        // v2.3.5 — JUST4PDF ▸ (CLI real; solo aparece si la selección lo permite).
        let pdfItem = NSMenuItem(title: "JUST4PDF", action: nil, keyEquivalent: "")
        pdfItem.tag = ContextTag.pdf.rawValue
        let pdfMenu = NSMenu(title: "JUST4PDF")
        let pdfMergeItem = NSMenuItem(title: "Unir PDFs en uno…", action: #selector(contextPdfQuickAction(_:)), keyEquivalent: "")
        pdfMergeItem.tag = 0
        pdfMergeItem.target = self
        pdfMenu.addItem(pdfMergeItem)
        let pdfCompressItem = NSMenuItem(title: "Comprimir", action: nil, keyEquivalent: "")
        pdfCompressItem.tag = 9
        let pdfCompressMenu = NSMenu(title: "Comprimir")
        let pdfLevels: [(String, Int)] = [("Bajo", 10), ("Medio", 11), ("Alto", 12)]
        for level in pdfLevels {
            let item = NSMenuItem(title: level.0, action: #selector(contextPdfQuickAction(_:)), keyEquivalent: "")
            item.tag = level.1
            item.target = self
            pdfCompressMenu.addItem(item)
        }
        pdfCompressItem.submenu = pdfCompressMenu
        pdfMenu.addItem(pdfCompressItem)
        let pdfExportItem = NSMenuItem(title: "Exportar páginas a imágenes…", action: #selector(contextPdfQuickAction(_:)), keyEquivalent: "")
        pdfExportItem.tag = 1
        pdfExportItem.target = self
        pdfMenu.addItem(pdfExportItem)
        let pdfImagesItem = NSMenuItem(title: "Crear PDF con estas imágenes…", action: #selector(contextPdfQuickAction(_:)), keyEquivalent: "")
        pdfImagesItem.tag = 2
        pdfImagesItem.target = self
        pdfMenu.addItem(pdfImagesItem)
        pdfMenu.addItem(.separator())
        let pdfOpenItem = NSMenuItem(title: "Abrir con JUST4PDF", action: #selector(contextPdfQuickAction(_:)), keyEquivalent: "")
        pdfOpenItem.tag = 3
        pdfOpenItem.target = self
        pdfMenu.addItem(pdfOpenItem)
        pdfItem.submenu = pdfMenu
        menu.addItem(pdfItem)
        menu.addItem(.separator())
        add("Cortar", #selector(contextCutSelectionAction), tag: .cut)
        add("Copiar", #selector(contextCopySelectionAction), tag: .copy)
        add("Pegar", #selector(contextPasteItems), tag: .paste)
        add("Mover a la Papelera", #selector(contextDeleteToTrash), tag: .trash)
        add("Borrar inmediatamente", #selector(contextDeletePermanent), tag: .deletePermanent)
        menu.addItem(.separator())
        add("Copiar ruta", #selector(contextCopyPath), tag: .copyPath)
        add("Añadir a Favoritos", #selector(contextToggleFavoriteAction), tag: .favorite)
        add("Añadir a Ubicaciones", #selector(contextAddToLocationsAction), tag: .addLocation)
        add("Información", #selector(contextShowInfo), tag: .info)
        let tagsItem = NSMenuItem(title: "Etiquetas", action: nil, keyEquivalent: "")
        tagsItem.tag = ContextTag.tags.rawValue
        let tagsMenu = NSMenu(title: "Etiquetas")
        for (name, _) in Self.tagPalette {
            let item = NSMenuItem(title: name, action: #selector(contextApplyTag(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = name
            tagsMenu.addItem(item)
        }
        tagsMenu.addItem(.separator())
        let clearTagsItem = NSMenuItem(title: "Quitar etiquetas", action: #selector(contextClearTags), keyEquivalent: "")
        clearTagsItem.target = self
        tagsMenu.addItem(clearTagsItem)
        tagsItem.submenu = tagsMenu
        menu.addItem(tagsItem)
        let shareItem = NSMenuItem(title: "Compartir", action: nil, keyEquivalent: "")
        shareItem.tag = ContextTag.share.rawValue
        menu.addItem(shareItem)
        menu.addItem(.separator())
        // P3 diseño — las utilidades viven en un submenú «Herramientas».
        let toolsItem = NSMenuItem(title: "Herramientas", action: nil, keyEquivalent: "")
        toolsItem.tag = ContextTag.tools.rawValue
        let toolsMenu = NSMenu(title: "Herramientas")
        let toolEntries: [(title: String, action: Selector)] = [
            ("Renombrar en lote…", #selector(contextBatchRename)),
            ("Buscar duplicados…", #selector(contextFindDuplicates)),
            ("Ordenar esta carpeta…", #selector(contextOrderFolder)),
            ("Olvidar formato de esta carpeta", #selector(contextForgetFolderFormat))
        ]
        for entry in toolEntries {
            let item = NSMenuItem(title: entry.title, action: entry.action, keyEquivalent: "")
            item.target = self
            toolsMenu.addItem(item)
        }
        toolsItem.submenu = toolsMenu
        menu.addItem(toolsItem)
        // Ola 3 — workspaces (el submenú se reconstruye en menuNeedsUpdate).
        let workspacesItem = NSMenuItem(title: "Workspaces", action: nil, keyEquivalent: "")
        workspacesItem.tag = ContextTag.workspaces.rawValue
        workspacesItem.submenu = NSMenu(title: "Workspaces")
        menu.addItem(workspacesItem)
        for item in menu.items {
            item.target = self
        }
        return menu
    }

    // MARK: - Columnas configurables (Ola 2)

    /// Menú en la cabecera: mostrar/ocultar columnas, ajustar cada una al contenido y repartir a la ventana.
    private func configureColumnMenu() {
        let menu = NSMenu(title: "Columnas")
        menu.delegate = self
        for id in ["name", "size", "modified", "type"] {
            let item = NSMenuItem(title: Self.columnTitle(for: id), action: #selector(toggleColumnVisibility(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = id
            menu.addItem(item)
        }
        menu.addItem(.separator())
        for id in ["name", "size", "modified", "type"] {
            let item = NSMenuItem(
                title: "Ajustar «\(Self.columnTitle(for: id))» al contenido",
                action: #selector(sizeColumnToContent(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = id
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let fit = NSMenuItem(title: "Ajustar columnas a la ventana", action: #selector(fitColumnsToWidth), keyEquivalent: "")
        fit.target = self
        menu.addItem(fit)
        tableView.headerView?.menu = menu
    }

    /// v2.1.1 — «Ajustar «X» al contenido»: sin tocar el resto (también con doble clic en el divisor).
    @objc private func sizeColumnToContent(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let column = tableView.tableColumns.first(where: { $0.identifier.rawValue == id }) else { return }
        column.sizeToFit()
        markColumnsAdjustedByUser()
        tableView.reloadData()
    }

    nonisolated static func columnTitle(for id: String) -> String {
        switch id {
        case "name": return "Nombre"
        case "size": return "Tamaño"
        case "modified": return "Modificado"
        case "type": return "Tipo"
        default: return id
        }
    }

    @objc private func toggleColumnVisibility(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let column = tableView.tableColumns.first(where: { $0.identifier.rawValue == id }) else { return }
        column.isHidden.toggle()
        saveFormat()
    }

    /// v2.1 — anchos base de las columnas (proporción canónica para el reparto).
    static let baseColumnWidths: [String: CGFloat] = ["name": 180, "size": 66, "modified": 118, "type": 74]

    /// v2.1.1 — reparto proporcional de columnas contra el viewport real.
    /// Sin anchos manuales reparte desde las proporciones base; con anchos del usuario comprime
    /// respetando las proporciones que él dejó (solo cuando no caben).
    private func applyColumnFit(useCurrentProportions: Bool) {
        let visible = tableView.tableColumns.filter { !$0.isHidden }
        guard !visible.isEmpty else { return }
        // OJO: `tableView.bounds` crece con las columnas; el ancho útil es el del viewport.
        let viewport = tableView.enclosingScrollView?.contentSize.width ?? tableView.bounds.width
        let available = viewport - 26  // margen extra: el scroller vertical se superpone al borde
        guard available > 200 else { return }
        let weights = visible.map { column -> CGFloat in
            if useCurrentProportions {
                return max(column.width, 1)
            }
            return Self.baseColumnWidths[column.identifier.rawValue] ?? column.width
        }
        let baseTotal = weights.reduce(CGFloat(0), +)
        var widths: [(NSTableColumn, CGFloat)] = []
        var assigned: CGFloat = 0
        for (index, column) in visible.enumerated() {
            let floor: CGFloat = column.identifier.rawValue == "name" ? 110 : 52
            let width = max(floor, weights[index] * available / baseTotal)
            widths.append((column, width))
            assigned += width
        }
        if assigned > available, let first = widths.first {
            widths[0] = (first.0, max(110, first.1 - (assigned - available)))
        }
        isFittingColumns = true
        var didChange = false
        for (column, width) in widths {
            if abs(column.width - width) > 0.5 {
                didChange = true
            }
            column.width = width
        }
        isFittingColumns = false
        lastFittedViewport = viewport
        // Sin recargar, las celdas ya creadas conservan el frame viejo (texto solapado).
        if didChange {
            tableView.reloadData()
            // v2.1.1 — y re-tile explícito: sin él las celdas visibles conservaban el ancho
            // anterior (p. ej. «Folde»/«1D» tras un fit con viewport transitorio).
            tableView.tile()
        }
    }

    /// v2.1.1 — «Ajustar columnas a la ventana»: descarta los anchos manuales y reparte de nuevo.
    @objc private func fitColumnsToWidth() {
        userAdjustedColumns = false
        applyColumnFit(useCurrentProportions: false)
        saveFormat()
    }

    /// v2.1 — refit de columnas pedido desde el commander (tras ajustes de divisorias).
    func refreshColumnLayout() {
        fitColumnsIfNeeded()
    }

    /// v2.2 — reparto completo de nuevo (cambio de modo de paneles: el viewport cambia de
    /// golpe y cualquier reparto previo ya no vale).
    func invalidateColumnFit() {
        lastFittedViewport = 0
        fitColumnsIfNeeded()
    }

    /// v2.1.1 — durante el arranque el layout pasa por anchos transitorios (p. ej. paneles a
    /// 283pt antes de asentarse): un refit en ese instante deja las columnas encogidas. Este
    /// reintento vuelve a ajustar cuando el viewport ya es el definitivo.
    private func scheduleSettledColumnRefit() {
        settledRefitWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.fitColumnsIfNeeded() }
        settledRefitWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        fitColumnsIfNeeded()
        scheduleSettledColumnRefit()
    }

    private var lastFittedViewport: CGFloat = 0
    private var settledRefitWorkItem: DispatchWorkItem?

    /// v2.1 — si las columnas no caben en el ancho visible (p. ej. con el árbol de panel
    /// apretando la tabla) o el viewport cambió, se reparten proporcionalmente.
    /// v2.1.1 — con anchos manuales solo se comprime cuando el viewport cambia (nunca mientras
    /// el usuario arrastra bordes; si se pasa, aparece scroll horizontal como en Finder).
    private func fitColumnsIfNeeded() {
        let visible = tableView.tableColumns.filter { !$0.isHidden }
        guard !visible.isEmpty else { return }
        let viewport = tableView.enclosingScrollView?.contentSize.width ?? tableView.bounds.width
        guard viewport > 100 else { return }
        let total = visible.reduce(CGFloat(0)) { $0 + $1.width }
        let viewportChanged = abs(viewport - lastFittedViewport) > 2
        if userAdjustedColumns {
            if viewportChanged {
                if total > viewport - 8 {
                    applyColumnFit(useCurrentProportions: true)
                } else {
                    lastFittedViewport = viewport
                }
            }
        } else if viewportChanged || total > viewport - 8 {
            applyColumnFit(useCurrentProportions: false)
        }
    }

    /// v2.1.1 — el usuario ha tocado los anchos: se recuerdan por carpeta (con pequeño retardo).
    func markColumnsAdjustedByUser() {
        guard !isFittingColumns, !isRestoringFormat else { return }
        userAdjustedColumns = true
        lastFittedViewport = tableView.enclosingScrollView?.contentSize.width ?? lastFittedViewport
        columnResizeSaveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveFormat() }
        columnResizeSaveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    func tableViewColumnDidResize(_ notification: Notification) {
        // v2.1.1 — el marcado de «anchos del usuario» lo hace la cabecera SOLO en arrastres
        // reales de un divisor (aquí llegaban también los cambios programáticos/transitorios).
    }

    private func currentColumnWidths() -> [String: CGFloat] {
        var widths: [String: CGFloat] = [:]
        for column in tableView.tableColumns {
            widths[column.identifier.rawValue] = column.width
        }
        return widths
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === tableView.headerView?.menu {
            for item in menu.items {
                guard let id = item.representedObject as? String,
                      let column = tableView.tableColumns.first(where: { $0.identifier.rawValue == id }) else { continue }
                item.state = column.isHidden ? .off : .on
            }
            return
        }
        if menu === contextMenu {
            rebuildWorkspacesSubmenu(in: menu)
            rebuildOpenWithSubmenu(in: menu)
            rebuildShareSubmenu(in: menu)
            updateContextMenuState(menu)
        }
    }

    /// v2.1.1 — habilitados y títulos dinámicos del menú contextual.
    private func updateContextMenuState(_ menu: NSMenu) {
        let selected = selectedURLs()
        let singleDir = singleSelectedDirectory()
        let target = contextTargetURL() ?? selected.first ?? currentURL
        let isFavorite = isFavoriteProvider?(target) ?? false
        let pasteboard = NSPasteboard.general
        let canPaste = pasteboard.canReadItem(withDataConformingToTypes: [
            NSPasteboard.PasteboardType.fileURL.rawValue,
            NSPasteboard.PasteboardType.string.rawValue
        ])
        for item in menu.items {
            switch ContextTag(rawValue: item.tag) {
            case .openInTab, .openInOther, .openWith, .openTerminal:
                item.isEnabled = singleDir != nil
            case .quickLook, .showInFinder, .copyPath, .duplicate, .compress, .cut, .copy, .trash, .deletePermanent:
                item.isEnabled = !selected.isEmpty
            case .rename:
                item.isEnabled = selected.count == 1
            case .paste:
                item.isEnabled = canPaste
            case .favorite:
                item.title = isFavorite ? "Quitar de Favoritos" : "Añadir a Favoritos"
                item.isEnabled = true
            case .tags:
                item.isEnabled = !selected.isEmpty
            case .pict:
                // v2.3.4 — el submenú solo APARECE cuando la selección trae imágenes.
                let hasImages = !PictQuickActions.images(in: selected).isEmpty
                item.isHidden = !hasImages
                item.isEnabled = hasImages
                item.submenu?.items.forEach { $0.isEnabled = hasImages }
            case .pdf:
                // v2.3.5 — visibilidad y habilitados del submenú JUST4PDF.
                configurePdfSubmenu(item, selection: selected)
            default:
                item.isEnabled = true
            }
        }
    }

    /// v2.3.5 — reglas del submenú «JUST4PDF ▸»: solo aparece si hay una acción usable.
    private func configurePdfSubmenu(_ item: NSMenuItem, selection: [URL]) {
        let pdfs = selection.filter { $0.pathExtension.lowercased() == "pdf" }
        let images = PictQuickActions.images(in: selection)
        let onlyImages = !selection.isEmpty && pdfs.isEmpty && images.count == selection.count
        let hasBridge = Just4PdfActions.isAvailable
        let hasApp = Just4PdfActions.appURL() != nil

        let mergeOK = hasBridge && pdfs.count >= 2
        let compressOK = hasBridge && !pdfs.isEmpty
        let exportOK = hasBridge && pdfs.count == 1
        let imagesOK = hasBridge && onlyImages && images.count >= 2
        let openOK = hasApp && !pdfs.isEmpty

        item.isHidden = !(mergeOK || compressOK || exportOK || imagesOK || openOK)
        guard let submenu = item.submenu else { return }
        for entry in submenu.items {
            switch entry.tag {
            case 0: entry.isEnabled = mergeOK
            case 9:
                entry.isEnabled = compressOK
                entry.submenu?.items.forEach { $0.isEnabled = compressOK }
            case 1: entry.isEnabled = exportOK
            case 2: entry.isEnabled = imagesOK
            case 3: entry.isEnabled = openOK
            default: break
            }
        }
    }

    /// v2.1.1 — «Abrir con ▸»: aplicaciones que pueden abrir el elemento seleccionado.
    private func rebuildOpenWithSubmenu(in menu: NSMenu) {
        guard let item = menu.items.first(where: { $0.tag == ContextTag.openWith.rawValue }) else { return }
        let submenu = NSMenu(title: "Abrir con")
        var apps: [URL] = []
        if let target = contextTargetURL() ?? selectedURLs().first {
            apps = NSWorkspace.shared.urlsForApplications(toOpen: target).sorted {
                $0.deletingPathExtension().lastPathComponent.localizedCaseInsensitiveCompare($1.deletingPathExtension().lastPathComponent) == .orderedAscending
            }
        }
        for app in apps.prefix(10) {
            let entry = NSMenuItem(title: app.deletingPathExtension().lastPathComponent, action: #selector(contextOpenWithApplication(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = app
            let icon = NSWorkspace.shared.icon(forFile: app.path)
            icon.size = NSSize(width: 16, height: 16)
            entry.image = icon
            submenu.addItem(entry)
        }
        if submenu.items.isEmpty {
            let empty = NSMenuItem(title: "Sin aplicaciones", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        }
        item.submenu = submenu
    }

    /// v2.1.1 — «Compartir ▸»: servicios del sistema para la selección.
    private func rebuildShareSubmenu(in menu: NSMenu) {
        guard let item = menu.items.first(where: { $0.tag == ContextTag.share.rawValue }) else { return }
        let submenu = NSMenu(title: "Compartir")
        let items: [Any] = selectedURLs().isEmpty ? [currentURL] : selectedURLs()
        let services = NSSharingService.sharingServices(forItems: items)
        for service in services.prefix(10) {
            let entry = NSMenuItem(title: service.menuItemTitle, action: #selector(contextShareWithService(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = service
            entry.image = service.image
            submenu.addItem(entry)
        }
        if submenu.items.isEmpty {
            let empty = NSMenuItem(title: "Sin servicios disponibles", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        }
        item.submenu = submenu
    }

    /// Ola 3 — lista los workspaces guardados dentro del menú contextual.
    private func rebuildWorkspacesSubmenu(in menu: NSMenu) {
        guard let item = menu.item(withTitle: "Workspaces") else { return }
        let submenu = NSMenu(title: "Workspaces")
        let workspaces = WorkspaceStore.shared.all()
        for workspace in workspaces {
            let entry = NSMenuItem(title: workspace.name, action: #selector(contextRestoreWorkspace(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = workspace.name
            submenu.addItem(entry)
        }
        if !workspaces.isEmpty {
            submenu.addItem(.separator())
        }
        let save = NSMenuItem(title: "Guardar workspace actual…", action: #selector(contextSaveWorkspace), keyEquivalent: "")
        save.target = self
        submenu.addItem(save)
        item.submenu = submenu
    }

    @objc private func contextSaveWorkspace() {
        activatePanel()
        NotificationCenter.default.post(name: .j4fWorkspaceSave, object: nil)
    }

    @objc private func contextRestoreWorkspace(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        activatePanel()
        NotificationCenter.default.post(name: .j4fWorkspaceRestore, object: nil, userInfo: ["name": name])
    }

    private func addColumn(id: String, title: String, width: CGFloat) {
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(rawValue: id))
        col.title = title
        col.width = width
        // v2.1.1 — el usuario puede arrastrar los bordes: topes sanos y sin colapso accidental.
        col.minWidth = (id == "name") ? 110 : 52
        col.maxWidth = 1600
        col.resizingMask = [.userResizingMask]
        col.sortDescriptorPrototype = NSSortDescriptor(key: id, ascending: true)
        tableView.addTableColumn(col)
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private func loadDirectory(_ url: URL, pushHistory: Bool) {
        // v2.0 — folder formats: al navegar (o en la primera carga) se restaura la vista guardada.
        if url != currentURL || !didApplyInitialFormat {
            didApplyInitialFormat = true
            restoreFormat(for: url)
        }
        if flatView {
            loadFlatView(url, pushHistory: pushHistory)
            return
        }
        flatLoading = false
        loadTask?.cancel()
        searchTask?.cancel()
        pendingRefreshWorkItem?.cancel()
        pendingSearchWorkItem?.cancel()
        quickFilter = ""
        hideQuickFilterHUD()
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
        updateHeaderTitle(for: url)
        onStatus?("Cargando \(url.path)...")
        allRows.removeAll(keepingCapacity: true)
        rows.removeAll(keepingCapacity: true)
        tableView.reloadData()
        rowCountLabel.stringValue = "0 elemento(s)"
        emptyStateLabel.isHidden = true

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
                    if self.searchQuery.isEmpty {
                        self.applySortAndReload()
                        self.onStatus?("\(total) elemento(s) en \(url.path)")
                    } else {
                        self.startDeepSearch(query: self.searchQuery)
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    guard self.loadToken == token else { return }
                    self.onStatus?("Error cargando carpeta: \(J4FError.from(error).userMessage)")
                }
            }
        }
    }

    // MARK: - Vista aplanada (v1.2, «flat view» estilo Directory Opus)

    /// ¿Está activa la vista aplanada en este panel?
    var flatViewActive: Bool { flatView }

    /// Activa/desactiva la vista aplanada (fuente: índice FTS5; muestra los ficheros del subárbol).
    func setFlatView(_ enabled: Bool) {
        guard flatView != enabled else { return }
        flatView = enabled
        flatToggleButton.state = enabled ? .on : .off
        flatToggleButton.contentTintColor = enabled ? J4FDesign.brand : .secondaryLabelColor
        pendingFlatRefreshWorkItem?.cancel()
        if enabled {
            onStatus?("Vista aplanada activada — indexando si hace falta…")
            loadFlatView(currentURL, pushHistory: false)
        } else {
            flatRows.removeAll(keepingCapacity: true)
            loadDirectory(currentURL, pushHistory: false)
        }
        saveFormat()
    }

    @objc private func toggleFlatViewAction() {
        setFlatView(flatToggleButton.state == .on)
    }

    /// v2.1.1 — reaplica los tints de marca (al cambiar el estilo visual en Ajustes).
    func reapplyBrandStyle() {
        flatToggleButton.contentTintColor = flatView ? J4FDesign.brand : .secondaryLabelColor
    }

    // MARK: - Folder formats (v2.0: recordar la vista por carpeta)

    /// v2.1.1 — la dirección vive en UNA sola barra por panel: breadcrumb navegable que pasa a
    /// campo editable con doble clic (o ⌘L), más atrás/adelante en el propio panel.
    private func updateHeaderTitle(for url: URL) {
        updateBreadcrumb(for: url)
        addressBackButton.isEnabled = canGoBack
        addressForwardButton.isEnabled = canGoForward
        addressPathContainer.toolTip = "\(url.path) — doble clic para escribir una ruta (⌘L)"
        if isEditingAddress {
            // Navegación externa mientras se edita: la barra vuelve al modo ruta.
            endAddressEditing(updateField: false)
        }
    }

    // MARK: - Edición de la dirección (v2.1.1)

    /// ⌘L — activa la edición de la ruta en este panel (el foco pasa al campo).
    func beginEditingPath() {
        guard view.window != nil, !isEditingAddress else { return }
        isEditingAddress = true
        pathEditField.stringValue = currentURL.path
        pathEditField.isHidden = false
        breadcrumbRow.isHidden = true
        view.window?.makeFirstResponder(pathEditField)
        pathEditField.currentEditor()?.selectAll(nil)
    }

    @objc private func commitPathEditing() {
        guard isEditingAddress else { return }
        let value = pathEditField.stringValue
        endAddressEditing(updateField: false)
        openPath(value)
        focusTable()
    }

    private func cancelAddressEditing() {
        guard isEditingAddress else { return }
        endAddressEditing(updateField: true)
        focusTable()
    }

    private func endAddressEditing(updateField: Bool) {
        isEditingAddress = false
        pathEditField.isHidden = true
        breadcrumbRow.isHidden = false
        if updateField {
            pathEditField.stringValue = ""
        }
    }

    @objc private func addressDoubleClicked() {
        activatePanel()
        beginEditingPath()
    }

    @objc private func addressBackPressed() {
        activatePanel()
        goBack()
    }

    @objc private func addressForwardPressed() {
        activatePanel()
        goForward()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, field == pathEditField else { return }
        // Enter ya pasó por commitPathEditing (isEditingAddress = false); aquí solo se cubre
        // la pérdida de foco (clic fuera), que equivale a cancelar.
        if isEditingAddress {
            cancelAddressEditing()
        }
    }

    /// Ola 1 — breadcrumb clicable (clic en un segmento para saltar a esa carpeta).
    private func updateBreadcrumb(for url: URL) {
        for view in breadcrumbRow.arrangedSubviews {
            breadcrumbRow.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        breadcrumbURLs.removeAll(keepingCapacity: true)
        let components = url.standardizedFileURL.pathComponents
        var accumulated = ""
        for (index, component) in components.enumerated() {
            if component == "/" {
                accumulated = "/"
            } else {
                accumulated = (accumulated as NSString).appendingPathComponent(component)
            }
            let isLast = index == components.count - 1
            let button = NSButton(title: component == "/" ? "/" : component, target: self, action: #selector(breadcrumbClicked(_:)))
            button.bezelStyle = .inline
            button.controlSize = .small
            button.font = .systemFont(ofSize: 11, weight: isLast ? .semibold : .regular)
            button.toolTip = accumulated
            button.isEnabled = !isLast
            breadcrumbURLs.append(URL(fileURLWithPath: accumulated, isDirectory: true))
            button.tag = breadcrumbURLs.count - 1
            // v2.1.1 — la carpeta actual (último segmento) no se comprime; los ancestros sí.
            button.setContentCompressionResistancePriority(isLast ? .defaultHigh : .defaultLow, for: .horizontal)
            button.lineBreakMode = .byTruncatingMiddle
            breadcrumbRow.addArrangedSubview(button)
            if !isLast {
                let chevron = NSTextField(labelWithString: "›")
                chevron.font = .systemFont(ofSize: 11)
                chevron.textColor = .tertiaryLabelColor
                breadcrumbRow.addArrangedSubview(chevron)
            }
        }
    }

    @objc private func breadcrumbClicked(_ sender: NSButton) {
        guard sender.tag >= 0, sender.tag < breadcrumbURLs.count else { return }
        activatePanel()
        openPath(breadcrumbURLs[sender.tag].path)
    }

    /// Restaura el formato guardado de una carpeta (sin disparar guardados intermedios).
    private func restoreFormat(for url: URL) {
        let format = folderFormatStore.format(for: url.standardizedFileURL.path)
        isRestoringFormat = true
        defer { isRestoringFormat = false }
        // v2.1.1 — sin anchos guardados se vuelve al reparto automático.
        userAdjustedColumns = false
        guard let format else {
            lastFittedViewport = tableView.enclosingScrollView?.contentSize.width ?? lastFittedViewport
            return
        }

        sortColumn = format.sortColumn
        ascending = format.ascending
        tableView.sortDescriptors = [NSSortDescriptor(key: format.sortColumn, ascending: format.ascending)]
        includeHiddenFiles = format.includeHidden
        if flatView != format.flatView {
            flatView = format.flatView
            flatToggleButton.state = format.flatView ? .on : .off
            flatToggleButton.contentTintColor = format.flatView ? J4FDesign.brand : .secondaryLabelColor
        }
        for column in tableView.tableColumns {
            column.isHidden = format.hiddenColumns?.contains(column.identifier.rawValue) ?? false
        }
        if let widths = format.columnWidths, !widths.isEmpty {
            isFittingColumns = true
            for column in tableView.tableColumns {
                if let width = widths[column.identifier.rawValue] {
                    column.width = max(column.minWidth, min(column.maxWidth, width))
                }
            }
            isFittingColumns = false
            userAdjustedColumns = true
        }
        lastFittedViewport = tableView.enclosingScrollView?.contentSize.width ?? lastFittedViewport
        applyGalleryMode(format.viewMode == "gallery")
    }

    /// Guarda el formato actual del panel para su carpeta (tras cambios del usuario).
    private func saveFormat() {
        guard !isRestoringFormat else { return }
        folderFormatStore.set(
            FolderFormat(
                flatView: flatView,
                sortColumn: sortColumn,
                ascending: ascending,
                includeHidden: includeHiddenFiles,
                hiddenColumns: tableView.tableColumns.filter { $0.isHidden }.map { $0.identifier.rawValue },
                viewMode: viewMode == .gallery ? "gallery" : nil,
                columnWidths: userAdjustedColumns ? currentColumnWidths() : nil
            ),
            for: currentURL.standardizedFileURL.path
        )
    }

    /// Olvida el formato guardado de la carpeta actual (menú contextual).
    @objc private func contextForgetFolderFormat() {
        activatePanel()
        folderFormatStore.remove(for: currentURL.standardizedFileURL.path)
        onStatus?("Formato olvidado para \(currentURL.path).")
    }

    /// Carga aplanada: consulta el índice (crawl cooperativo si la carpeta no está lista) y
    /// muestra todos los ficheros del subárbol; la columna «Tipo» pasa a ser la ruta relativa.
    /// Con `silent` (refresco del watcher) se conserva el contenido actual hasta tener el nuevo
    /// (sin parpadeos ni «0 items»).
    private func loadFlatView(_ url: URL, pushHistory: Bool, silent: Bool = false) {
        flatLoading = true
        loadTask?.cancel()
        searchTask?.cancel()
        pendingRefreshWorkItem?.cancel()
        pendingSearchWorkItem?.cancel()
        pendingFlatRefreshWorkItem?.cancel()
        quickFilter = ""
        hideQuickFilterHUD()
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
        updateHeaderTitle(for: url)
        if !silent {
            onStatus?("Aplanando \(url.path)…")
            rows.removeAll(keepingCapacity: true)
            tableView.reloadData()
            rowCountLabel.stringValue = "0 elemento(s)"
            emptyStateLabel.isHidden = true
        }

        let token = loadToken
        let includeHidden = includeHiddenFiles
        loadTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let hits = try await self.indexedSearch.flatEntriesPreparing(
                    under: url,
                    includeHidden: includeHidden,
                    onProgress: { [weak self] displayPath, scanned in
                        Task { @MainActor in
                            self?.onStatus?("Indexando «\(displayPath)»… \(scanned) entrada(s).")
                        }
                    }
                )
                guard !Task.isCancelled else { return }
                let mapped = hits.map { hit in
                    FileRow(
                        url: URL(fileURLWithPath: hit.path),
                        name: hit.name,
                        isDirectory: hit.isDirectory,
                        sizeBytes: hit.isDirectory ? nil : hit.sizeBytes,
                        modifiedDate: hit.modifiedTimeInterval > 0 ? Date(timeIntervalSince1970: hit.modifiedTimeInterval) : nil,
                        typeDescription: Self.relativeDirectory(of: hit.path, under: url.path)
                    )
                }
                await MainActor.run {
                    guard self.loadToken == token else { return }
                    self.flatLoading = false
                    self.flatRows = mapped
                    self.applySortAndReload()
                    let capped = mapped.count >= 50000 ? " (límite de vista alcanzado)" : ""
                    self.onStatus?("Vista aplanada: \(mapped.count) fichero(s) bajo \(url.path)\(capped)")
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    guard self.loadToken == token else { return }
                    self.flatLoading = false
                    self.onStatus?("No se pudo aplanar: \(J4FError.from(error).userMessage)")
                }
            }
        }
    }

    /// Ruta relativa de la carpeta contenedora de `path` bajo `root` («·» si es la raíz).
    nonisolated static func relativeDirectory(of path: String, under root: String) -> String {
        let directory = (path as NSString).deletingLastPathComponent
        guard directory.count > root.count, directory.hasPrefix(root) else { return "·" }
        let relative = String(directory.dropFirst(root.count + 1))
        return relative.isEmpty ? "·" : relative
    }

    private func scheduleFlatViewRefresh() {
        pendingFlatRefreshWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.flatView else { return }
            if self.flatLoading {
                // Hay una carga aplanada en vuelo: no la cancelamos (evita livelock con el
                // watcher); reintentamos en cuanto termine.
                self.scheduleFlatViewRefresh()
                return
            }
            self.loadFlatView(self.currentURL, pushHistory: false, silent: true)
        }
        pendingFlatRefreshWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    // MARK: - Tamaños de carpeta (v1.2, background)

    private var sizeColumnIndex: Int {
        tableView.tableColumns.firstIndex { $0.identifier.rawValue == "size" } ?? -1
    }

    private func requestFolderSize(for url: URL) {
        let path = url.standardizedFileURL.path
        guard !folderSizeRequests.contains(path) else { return }
        folderSizeRequests.insert(path)
        Task { [weak self] in
            let size = await FolderSizeCalculator.shared.size(of: url, includeHidden: false)
            await MainActor.run {
                guard let self else { return }
                self.folderSizeRequests.remove(path)
                self.applyFolderSize(size, forPath: path)
            }
        }
    }

    private func applyFolderSize(_ size: Int64, forPath path: String) {
        updateFolderSize(in: &allRows, path: path, size: size)
        updateFolderSize(in: &flatRows, path: path, size: size)
        guard let idx = rows.firstIndex(where: { $0.url.standardizedFileURL.path == path }) else { return }
        rows[idx].folderSizeBytes = size
        let column = sizeColumnIndex
        if column >= 0 {
            tableView.reloadData(forRowIndexes: IndexSet(integer: idx), columnIndexes: IndexSet(integer: column))
        }
    }

    private func updateFolderSize(in array: inout [FileRow], path: String, size: Int64) {
        if let idx = array.firstIndex(where: { $0.url.standardizedFileURL.path == path }) {
            array[idx].folderSizeBytes = size
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
        if viewMode == .gallery {
            let urls = selectedURLs()
            guard urls.count == 1, let url = urls.first else { return }
            if isDirectory(url) {
                loadDirectory(url, pushHistory: true)
            } else {
                NSWorkspace.shared.open(url)
            }
            return
        }
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

    // MARK: - Drag & drop (Ola 1)

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
        guard row >= 0, row < rows.count else { return nil }
        return rows[row].url as NSURL
    }

    func tableView(
        _ tableView: NSTableView,
        validateDrop info: NSDraggingInfo,
        proposedRow row: Int,
        proposedDropOperation dropOperation: NSTableView.DropOperation
    ) -> NSDragOperation {
        let urls = draggedURLs(from: info)
        guard !urls.isEmpty else { return [] }
        if dropOperation == .on, row >= 0, row < rows.count, rows[row].isDirectory {
            guard canDrop(urls, into: rows[row].url) else { return [] }
            return preferredDropOperation(info)
        }
        // Fondo de la tabla: destino = carpeta del panel.
        guard canDrop(urls, into: currentURL) else { return [] }
        tableView.setDropRow(-1, dropOperation: .on)
        return preferredDropOperation(info)
    }

    func tableView(
        _ tableView: NSTableView,
        acceptDrop info: NSDraggingInfo,
        row: Int,
        dropOperation: NSTableView.DropOperation
    ) -> Bool {
        let urls = draggedURLs(from: info)
        guard !urls.isEmpty else { return false }
        let target: URL = (row >= 0 && row < rows.count && rows[row].isDirectory) ? rows[row].url : currentURL
        guard canDrop(urls, into: target) else { return false }
        onDropRequest?(urls, target, preferredDropOperation(info) == .copy)
        return true
    }

    private func draggedURLs(from info: NSDraggingInfo) -> [URL] {
        let objects = info.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]
        return objects ?? []
    }

    /// Evita soltar una carpeta sobre sí misma o sobre su propio subárbol.
    private func canDrop(_ urls: [URL], into target: URL) -> Bool {
        let targetPath = target.standardizedFileURL.path
        for url in urls {
            let path = url.standardizedFileURL.path
            if path == targetPath { return false }
            if targetPath.hasPrefix(path + "/") { return false }
        }
        return true
    }

    /// Interior por defecto mueve (⌥ copia); desde fuera copia (⌘ mueve).
    private func preferredDropOperation(_ info: NSDraggingInfo) -> NSDragOperation {
        let isLocal = info.draggingSource is NSTableView
        let flags = NSEvent.modifierFlags
        if flags.contains(.option) { return .copy }
        if flags.contains(.command) { return .move }
        return isLocal ? .move : .copy
    }

    // MARK: - Hover por fila (Ola 3)

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        HoverRowView()
    }

    private func handleHoverEvent(_ event: NSEvent) {
        guard event.window === view.window, event.type == .mouseMoved else {
            updateHoveredRow(-1)
            return
        }
        let local = tableView.convert(event.locationInWindow, from: nil)
        guard tableView.bounds.contains(local) else {
            updateHoveredRow(-1)
            return
        }
        updateHoveredRow(tableView.row(at: local))
    }

    private func updateHoveredRow(_ index: Int) {
        guard hoveredRow != index else { return }
        hoveredRow = index
        for row in 0..<rows.count {
            if let view = tableView.rowView(atRow: row, makeIfNecessary: false) as? HoverRowView {
                view.hovered = (row == index)
            }
        }
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

        // v1.2 — tamaño de carpeta en background (solo para lo visible).
        if columnId == "size" && item.isDirectory && item.folderSizeBytes == nil {
            requestFolderSize(for: item.url)
        }

        let identifier = NSUserInterfaceItemIdentifier("Cell-\(columnId)")
        // v2.1.1 — sin reciclado de celdas: las reutilizadas conservaban medidas viejas tras un
        // ajuste de columnas (p. ej. «Folde» recortado aunque la columna ya era ancha, incluso
        // con reloadData+tile). Con ~30 filas visibles, crear celdas nuevas no cuesta nada.
        let cell = NSTableCellView()
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

        label.alignment = columnId == "size" ? .right : .left
        label.stringValue = text
        label.lineBreakMode = .byTruncatingMiddle
        // v2.1 — OJO: con attributedStringValue el lineBreakMode del label se ignora; hay que
        // fijar el truncado en el párrafo o las celdas envuelven y se solapan entre filas.
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingMiddle
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: label.font as Any,
            .paragraphStyle: paragraph
        ]
        if columnId == "name", let tagColor = Self.tagColor(forIndex: tagColorIndex(for: item.url)) {
            // Etiqueta Finder: punto de color + nombre neutro (legible también con la fila seleccionada).
            let attributed = NSMutableAttributedString(
                string: "●  ",
                attributes: baseAttributes.merging([.foregroundColor: tagColor]) { _, new in new }
            )
            attributed.append(NSAttributedString(
                string: item.name,
                attributes: baseAttributes.merging([.foregroundColor: NSColor.labelColor]) { _, new in new }
            ))
            label.attributedStringValue = attributed
        } else {
            var attributes = baseAttributes
            attributes[.foregroundColor] = item.isDirectory && columnId == "name" ? NSColor.controlAccentColor : NSColor.labelColor
            label.attributedStringValue = NSAttributedString(string: text, attributes: attributes)
        }

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
            // Ola 1 — miniatura real (imagen/PDF/vídeo) con caché; si no, icono del sistema.
            if !item.isDirectory, let thumbnail = sharedThumbnailCache.cached(for: item.url) {
                icon.image = thumbnail
            } else {
                icon.image = sharedFileIconCache.icon(for: item)
                if !item.isDirectory {
                    let url = item.url
                    sharedThumbnailCache.request(for: url) { [weak self] in
                        self?.reloadRow(forPath: url.standardizedFileURL.path, columnID: "name")
                    }
                }
            }
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
        onSelectionChanged?()
    }

    /// Ola 2 — abrir la selección con la app por defecto (F4).
    func openSelection() {
        openSelected()
    }

    /// Ola 1 — mueve la selección (para navegar el preview QuickLook con las flechas).
    func moveSelection(by delta: Int) {
        guard !rows.isEmpty else { return }
        let current = tableView.selectedRow
        let base = current >= 0 ? current : (delta > 0 ? -1 : rows.count)
        let next = max(0, min(rows.count - 1, base + delta))
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard let descriptor = tableView.sortDescriptors.first else { return }
        sortColumn = descriptor.key ?? "name"
        ascending = descriptor.ascending
        applySortAndReload()
        saveFormat()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        // v2.1.1 — Esc en la barra de dirección cancela la edición (Enter lo gestiona la acción).
        if control == pathEditField {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                cancelAddressEditing()
                return true
            }
            return false
        }
        if commandSelector == #selector(insertNewline(_:)) {
            openSelected()
            return true
        }
        return false
    }

    private func applySortAndReload() {
        let selectedPaths = Set(selectedURLs().map { $0.standardizedFileURL.path })
        let base = flatView ? flatRows : allRows
        let filtered: [FileRow]
        if !searchQuery.isEmpty {
            filtered = searchRows
        } else if !quickFilter.isEmpty {
            let needle = Self.normalizedSearchText(quickFilter)
            filtered = base.filter { Self.normalizedSearchText($0.name).contains(needle) }
        } else {
            filtered = base
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
        rowCountLabel.stringValue = "\(rows.count) elemento(s)"
            + (flatView ? " · aplanada" : "")
            + (quickFilter.isEmpty ? "" : " · filtro «\(quickFilter)»")
        if viewMode == .gallery {
            collectionView.reloadData()
        }
        updateEmptyState()
        // v2.1 — si el ancho cambió (árbol de panel, ventana…), evita columnas cortadas.
        fitColumnsIfNeeded()
    }

    /// v2.0 — hits del índice para una consulta; con búsqueda semántica activa la IA expande
    /// la consulta en varios términos y se unen los resultados sin duplicados.
    /// `global` (⌘F) consulta todo el índice en lugar del subárbol del panel.
    private func indexedSearchRows(for query: String, root: URL, includeHidden: Bool, maxMatches: Int, global: Bool) async -> [FileRow]? {
        var queries: [String] = [query]
        if semanticSearchEnabled, let expander = semanticExpander {
            do {
                let expanded = try await expander.expand(query: query)
                if !expanded.isEmpty {
                    queries = expanded
                    onStatus?("IA: «\(query)» → \(expanded.joined(separator: " · "))")
                }
            } catch {
                logger.debug("Expansión semántica no disponible: \(error.localizedDescription, privacy: .public)")
            }
        }

        var rows: [FileRow] = []
        var seen = Set<String>()
        var anySuccess = false
        let ensureRoots = indexRootsProvider?() ?? [root]
        for term in queries {
            let progress: (String, Int64) -> Void = { [weak self] displayPath, scanned in
                Task { @MainActor in
                    self?.onStatus?("Indexando «\(displayPath)»… \(scanned) entrada(s).")
                }
            }
            let hits: [IndexedSearchService.Hit]?
            if global {
                hits = try? await indexedSearch.searchGlobalPreparing(
                    query: term,
                    ensureRoots: ensureRoots,
                    includeHidden: includeHidden,
                    limit: maxMatches,
                    onProgress: progress
                )
            } else {
                hits = try? await indexedSearch.searchPreparing(
                    query: term,
                    under: root,
                    includeHidden: includeHidden,
                    limit: maxMatches,
                    onProgress: progress
                )
            }
            guard let hits else { continue }
            anySuccess = true
            for hit in hits where seen.insert(hit.path).inserted {
                let relativePath: String
                if global {
                    relativePath = (hit.path as NSString).abbreviatingWithTildeInPath
                } else if hit.path.hasPrefix(root.path + "/") {
                    relativePath = String(hit.path.dropFirst(root.path.count + 1))
                } else {
                    relativePath = hit.name
                }
                rows.append(FileRow(
                    url: URL(fileURLWithPath: hit.path),
                    name: hit.name,
                    isDirectory: hit.isDirectory,
                    sizeBytes: hit.isDirectory ? nil : hit.sizeBytes,
                    modifiedDate: Date(timeIntervalSince1970: hit.modifiedTimeInterval),
                    typeDescription: "\(hit.isDirectory ? "Folder" : "Archivo") • \(relativePath)"
                ))
            }
        }
        return anySuccess ? rows : nil
    }

    private func startDeepSearch(query: String) {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            searchRows.removeAll(keepingCapacity: true)
            applySortAndReload()
            onSearchDidFinish?()
            return
        }

        onSearchWillStart?()

        let token = UUID()
        searchToken = token
        let root = currentURL
        let includeHidden = includeHiddenFiles
        let terms = Self.searchTerms(from: clean)
        let maxMatches = 5000
        let allowIndexLookup = true
        let global = isGlobalSearchActive?() ?? false

        let baseRows = flatView ? flatRows : allRows
        let quickRows = baseRows.filter { row in
            let normalizedName = Self.normalizedSearchText(row.name)
            return terms.allSatisfy { normalizedName.contains($0) }
        }
        searchRows = quickRows
        applySortAndReload()
        if global {
            onStatus?("Busqueda global: \(quickRows.count) coincidencias locales. Consultando todo el indice…")
        } else {
            onStatus?("Busqueda rapida: \(quickRows.count) coincidencias. Profundizando en \(root.path)...")
        }

        searchTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            if allowIndexLookup,
               let mapped = await self.indexedSearchRows(for: clean, root: root, includeHidden: includeHidden, maxMatches: maxMatches, global: global) {
                if Task.isCancelled { return }
                await MainActor.run {
                    guard self.searchToken == token else { return }
                    self.searchRows = mapped
                    self.applySortAndReload()
                    if global {
                        self.onStatus?("Busqueda global indexada: \(self.searchRows.count) coincidencias en todo el indice")
                    } else {
                        self.onStatus?("Busqueda indexada: \(self.searchRows.count) coincidencias en \(root.path)")
                    }
                    self.onSearchDidFinish?()
                }
                return
            }

            if global {
                // Sin índice no hay recorrido global razonable (sería barrer el home entero).
                await MainActor.run {
                    guard self.searchToken == token else { return }
                    self.onStatus?("Busqueda global: el indice no esta disponible; se muestran solo las coincidencias locales.")
                    self.onSearchDidFinish?()
                }
                return
            }

            let existing = Set(quickRows.map { $0.url.standardizedFileURL.path })
            let deepRows = await Self.parallelDeepSearch(
                root: root,
                terms: terms,
                includeHidden: includeHidden,
                maxMatches: maxMatches,
                excludingPaths: existing
            )

            if Task.isCancelled { return }

            await MainActor.run {
                guard self.searchToken == token else { return }
                var merged = quickRows
                merged.append(contentsOf: deepRows)

                var seen = Set<String>()
                let limited = merged.filter { row in
                    let path = row.url.standardizedFileURL.path
                    if seen.contains(path) { return false }
                    seen.insert(path)
                    return true
                }.prefix(maxMatches)

                self.searchRows = Array(limited)
                self.applySortAndReload()
                self.onStatus?("Busqueda completada: \(self.searchRows.count) coincidencias en \(root.path)")
                self.onSearchDidFinish?()
            }
        }
    }

    nonisolated private static func parallelDeepSearch(
        root: URL,
        terms: [String],
        includeHidden: Bool,
        maxMatches: Int,
        excludingPaths: Set<String>
    ) async -> [FileRow] {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isHiddenKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .localizedTypeDescriptionKey
        ]

        guard let topLevel = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsPackageDescendants]
        ) else {
            return []
        }

        var matches: [FileRow] = []
        var seen = excludingPaths
        var subdirectories: [URL] = []

        for child in topLevel {
            if Task.isCancelled { return [] }
            guard let values = try? child.resourceValues(forKeys: keys) else { continue }
            if !includeHidden, values.isHidden == true { continue }

            if values.isDirectory == true {
                subdirectories.append(child)
            }

            if let row = makeSearchRowIfMatches(url: child, values: values, terms: terms, root: root),
               seen.insert(row.url.standardizedFileURL.path).inserted {
                matches.append(row)
                if matches.count >= maxMatches {
                    return matches
                }
            }
        }

        guard !subdirectories.isEmpty else { return matches }

        let workerCount = min(recommendedSearchWorkers(for: root), max(1, subdirectories.count))
        let perWorkerCap = max(250, (maxMatches / max(1, workerCount)) + 128)
        var buckets = Array(repeating: [URL](), count: workerCount)
        for (index, dir) in subdirectories.enumerated() {
            buckets[index % workerCount].append(dir)
        }

        await withTaskGroup(of: [FileRow].self) { group in
            for bucket in buckets where !bucket.isEmpty {
                group.addTask(priority: .utility) {
                    var bucketMatches: [FileRow] = []
                    for dir in bucket {
                        if Task.isCancelled { break }
                        scanSubtree(
                            root: root,
                            subtree: dir,
                            terms: terms,
                            includeHidden: includeHidden,
                            maxMatches: perWorkerCap,
                            output: &bucketMatches
                        )
                        if bucketMatches.count >= perWorkerCap {
                            break
                        }
                    }
                    return bucketMatches
                }
            }

            while let partial = await group.next() {
                if Task.isCancelled {
                    group.cancelAll()
                    break
                }
                for row in partial {
                    let path = row.url.standardizedFileURL.path
                    if seen.insert(path).inserted {
                        matches.append(row)
                        if matches.count >= maxMatches {
                            group.cancelAll()
                            return
                        }
                    }
                }
            }
        }

        return matches
    }

    nonisolated private static func scanSubtree(
        root: URL,
        subtree: URL,
        terms: [String],
        includeHidden: Bool,
        maxMatches: Int,
        output: inout [FileRow]
    ) {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isHiddenKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .localizedTypeDescriptionKey
        ]

        guard let enumerator = FileManager.default.enumerator(
            at: subtree,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsPackageDescendants]
        ) else {
            return
        }

        while let next = enumerator.nextObject() {
            if Task.isCancelled || output.count >= maxMatches { return }
            guard let url = next as? URL else { continue }
            guard let values = try? url.resourceValues(forKeys: keys) else { continue }
            if !includeHidden, values.isHidden == true {
                if values.isDirectory == true {
                    enumerator.skipDescendants()
                }
                continue
            }
            if let row = makeSearchRowIfMatches(url: url, values: values, terms: terms, root: root) {
                output.append(row)
            }
        }
    }

    nonisolated private static func makeSearchRowIfMatches(
        url: URL,
        values: URLResourceValues,
        terms: [String],
        root: URL
    ) -> FileRow? {
        let normalizedName = normalizedSearchText(url.lastPathComponent)
        guard terms.allSatisfy({ normalizedName.contains($0) }) else { return nil }

        let isDir = values.isDirectory == true
        let type = values.localizedTypeDescription ?? (isDir ? "Folder" : "Archivo")
        let relativePath: String
        if url.path.hasPrefix(root.path + "/") {
            relativePath = String(url.path.dropFirst(root.path.count + 1))
        } else {
            relativePath = url.lastPathComponent
        }
        return FileRow(
            url: url,
            name: url.lastPathComponent,
            isDirectory: isDir,
            sizeBytes: isDir ? nil : Int64(values.fileSize ?? 0),
            modifiedDate: values.contentModificationDate,
            typeDescription: "\(type) • \(relativePath)"
        )
    }

    nonisolated private static func recommendedSearchWorkers(for root: URL) -> Int {
        if let values = try? root.resourceValues(forKeys: [.volumeIsLocalKey, .volumeIsInternalKey]) {
            let isLocal = values.volumeIsLocal ?? true
            let isInternal = values.volumeIsInternal ?? false
            if isLocal && isInternal {
                return 8
            }
            if isLocal {
                return 4
            }
            return 2
        }
        return 4
    }

    nonisolated private static func searchTerms(from text: String) -> [String] {
        normalizedSearchText(text)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }

    nonisolated private static func normalizedSearchText(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
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
        // v2.1.1 — con autoenablesItems = false, este callback garantiza el estado del menú.
        if menu === contextMenu {
            rebuildWorkspacesSubmenu(in: menu)
            rebuildOpenWithSubmenu(in: menu)
            rebuildShareSubmenu(in: menu)
            updateContextMenuState(menu)
        }
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
            onStatus?("No se pudo crear carpeta: \(J4FError.from(error).userMessage)")
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
                onStatus?("Pegados \(pasted) elemento(s).")
            } else {
                onStatus?("No hay rutas válidas para pegar.")
            }
        } catch {
            onStatus?("No se pudo pegar: \(J4FError.from(error).userMessage)")
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

    // MARK: - Acciones del menú contextual ampliado (v2.1.1)

    private func singleSelectedDirectory() -> URL? {
        let selected = selectedURLs()
        guard selected.count == 1, isDirectory(selected[0]) else { return nil }
        return selected[0]
    }

    @objc private func contextOpenInNewTab() {
        guard let dir = singleSelectedDirectory() else { NSSound.beep(); return }
        tabURLs.append(dir)
        tabCustomTitles.append(nil)
        activeTabIndex = tabURLs.count - 1
        historyBack.removeAll()
        historyForward.removeAll()
        refreshTabsControl()
        loadDirectory(dir, pushHistory: false)
        onStatus?("Abierta en pestaña nueva: \(dir.lastPathComponent)")
    }

    @objc private func contextOpenInOtherPanel() {
        guard let dir = singleSelectedDirectory() else { NSSound.beep(); return }
        onOpenInOtherPanel?(dir)
    }

    @objc private func contextQuickLook() {
        onQuickLookRequested?()
    }

    @objc private func contextOpenInTerminal() {
        let directory = singleSelectedDirectory() ?? currentURL
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([directory], withApplicationAt: terminal, configuration: configuration) { [weak self] _, error in
            guard let error else { return }
            DispatchQueue.main.async {
                self?.onStatus?("No se pudo abrir Terminal: \(error.localizedDescription)")
            }
        }
    }

    @objc private func contextOpenWithApplication(_ sender: NSMenuItem) {
        guard let appURL = sender.representedObject as? URL else { return }
        let targets = selectedURLs()
        let items = targets.isEmpty ? [currentURL] : targets
        let configuration = NSWorkspace.OpenConfiguration()
        for url in items {
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration)
        }
        onStatus?("Abriendo \(items.count) elemento(s) con \(appURL.deletingPathExtension().lastPathComponent)…")
    }

    @objc private func contextShareWithService(_ sender: NSMenuItem) {
        guard let service = sender.representedObject as? NSSharingService else { return }
        let items: [Any] = selectedURLs().isEmpty ? [currentURL] : selectedURLs()
        service.perform(withItems: items)
    }

    @objc private func contextDuplicateSelection() {
        duplicateSelection()
    }

    @objc private func contextCompressSelection() {
        compressSelection()
    }

    @objc private func contextCopySelectionAction() {
        copySelectionToClipboard()
    }

    @objc private func contextToggleFavoriteAction() {
        let url = contextTargetURL() ?? selectedURLs().first ?? currentURL
        onToggleFavoriteRequested?(url)
    }

    @objc private func contextAddToLocationsAction() {
        let url = contextTargetURL() ?? selectedURLs().first ?? currentURL
        onAddLocationRequested?(url)
    }

    // MARK: - Portapapeles y operaciones rápidas (v2.1.1)

    /// v2.1.1 — tipos de portapapeles que marcan «cortar»: al pegar, los elementos se mueven
    /// (el propio y el de Finder, para que un corte hecho en Finder también mueva aquí).
    static let cutPasteboardType = NSPasteboard.PasteboardType("com.dmx83.just4folders.cut")
    static let finderCutType = NSPasteboard.PasteboardType("com.apple.finder.pboard.cut")

    /// ⌘C — copia al portapapeles como URLs de archivo (pegable en Finder y en esta app).
    func copySelectionToClipboard() {
        let selected = selectedURLs()
        guard !selected.isEmpty else { NSSound.beep(); return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(selected as [NSURL])
        onStatus?("Copiado(s) al portapapeles: \(selected.count)")
    }

    /// ⌘X — corta al portapapeles: al pegar, los elementos se MUEVEN (el corte se consume).
    func cutSelectionToClipboard() {
        let selected = selectedURLs()
        guard !selected.isEmpty else { NSSound.beep(); return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(selected as [NSURL])
        pasteboard.setData(Data(), forType: Self.cutPasteboardType)
        onStatus?("Cortado(s): \(selected.count) — se moverán al pegar.")
    }

    @objc private func contextCutSelectionAction() {
        cutSelectionToClipboard()
    }

    /// ⌘D — duplica la selección junto a los originales («nombre-1.ext», sin pisar nada).
    func duplicateSelection() {
        let selected = selectedURLs()
        guard !selected.isEmpty else { return }
        let fm = FileManager.default
        var created = 0
        for source in selected {
            let proposed = source.deletingLastPathComponent()
                .appendingPathComponent(source.lastPathComponent, isDirectory: isDirectory(source))
            let destination = availableDestination(for: proposed)
            do {
                try fm.copyItem(at: source, to: destination)
                created += 1
            } catch {
                onStatus?("No se pudo duplicar \(source.lastPathComponent): \(J4FError.from(error).userMessage)")
            }
        }
        if created > 0 {
            loadDirectory(currentURL, pushHistory: false)
            onStatus?("Duplicado(s): \(created)")
        }
    }

    /// v2.3.3 — acciones rápidas del submenú JUST4PICT (fichero nuevo; nunca sobrescribe).
    @objc private func contextPictQuickAction(_ sender: NSMenuItem) {
        let urls = PictQuickActions.images(in: selectedURLs())
        guard !urls.isEmpty else {
            NSSound.beep()
            return
        }
        let result: PictQuickActions.Result
        let verb: String
        switch sender.tag {
        case 0:
            result = PictQuickActions.convert(urls, to: "png")
            verb = "convertidas a PNG"
        case 1:
            result = PictQuickActions.convert(urls, to: "jpeg", extraArgs: ["-s", "formatOptions", "85"])
            verb = "convertidas a JPEG"
        default:
            result = PictQuickActions.resizeHalf(urls)
            verb = "redimensionadas al 50 %"
        }
        if result.failures == 0 {
            onStatus?("PICT: \(result.created.count) imagen(es) \(verb). Fichero nuevo junto al original.")
        } else {
            onStatus?("PICT: \(result.created.count) \(verb); \(result.failures) fallo(s).")
        }
        refreshCurrentDirectory()
    }

    /// v2.3.5 — acciones del submenú JUST4PDF (CLI en background; nunca sobrescribe).
    @objc private func contextPdfQuickAction(_ sender: NSMenuItem) {
        let selection = selectedURLs()
        let pdfs = selection.filter { $0.pathExtension.lowercased() == "pdf" }
        let images = PictQuickActions.images(in: selection)

        func finish(_ result: Just4PdfActions.OperationResult) {
            onStatus?(result.message)
            if result.success {
                refreshCurrentDirectory()
            } else {
                NSSound.beep()
            }
        }

        switch sender.tag {
        case 0:
            guard pdfs.count >= 2 else { NSSound.beep(); return }
            onStatus?("JUST4PDF: uniendo \(pdfs.count) PDFs…")
            Just4PdfActions.merge(pdfs, completion: finish)
        case 10, 11, 12:
            guard !pdfs.isEmpty else { NSSound.beep(); return }
            let level = sender.tag == 10 ? "low" : (sender.tag == 11 ? "medium" : "high")
            onStatus?("JUST4PDF: comprimiendo \(pdfs.count) PDF(s)…")
            Just4PdfActions.compressAll(pdfs, level: level, completion: finish)
        case 1:
            guard pdfs.count == 1, let pdf = pdfs.first else { NSSound.beep(); return }
            onStatus?("JUST4PDF: exportando páginas…")
            Just4PdfActions.pdfToImages(pdf, completion: finish)
        case 2:
            guard pdfs.isEmpty, images.count >= 2, images.count == selection.count else { NSSound.beep(); return }
            onStatus?("JUST4PDF: creando PDF…")
            Just4PdfActions.imagesToPDF(images, completion: finish)
        case 3:
            guard !pdfs.isEmpty else { NSSound.beep(); return }
            Just4PdfActions.openWith(pdfs) { [weak self] message in
                self?.onStatus?(message)
            }
        default:
            break
        }
    }

    /// «Comprimir» — zip nativo (/usr/bin/zip) junto a los originales.
    func compressSelection() {
        let selected = selectedURLs()
        guard !selected.isEmpty else { return }
        let baseName: String
        if selected.count == 1 {
            baseName = (selected[0].lastPathComponent as NSString).deletingPathExtension
        } else {
            baseName = "Archivo"
        }
        let destination = availableDestination(for: currentURL.appendingPathComponent(baseName + ".zip"))
        let allSameParent = selected.allSatisfy {
            $0.deletingLastPathComponent().standardizedFileURL == selected[0].deletingLastPathComponent().standardizedFileURL
        }
        let workDirectory = allSameParent ? selected[0].deletingLastPathComponent() : nil
        let absolutePaths = selected.map(\.path)
        let relativeNames = selected.map { $0.lastPathComponent }
        onStatus?("Comprimiendo \(selected.count) elemento(s)…")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            process.currentDirectoryURL = workDirectory
            process.arguments = ["-r", "-y", "-q", destination.path] + (workDirectory != nil ? relativeNames : absolutePaths)
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
                process.waitUntilExit()
                let ok = process.terminationStatus == 0
                DispatchQueue.main.async {
                    guard let self else { return }
                    if ok {
                        self.loadDirectory(self.currentURL, pushHistory: false)
                        self.onStatus?("Creado \(destination.lastPathComponent)")
                    } else {
                        self.onStatus?("No se pudo comprimir (zip salió con estado \(process.terminationStatus))")
                        NSSound.beep()
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.onStatus?("No se pudo comprimir: \(J4FError.from(error).userMessage)")
                }
            }
        }
    }

    // Selectores estándar (menú Edición): funcionan cuando el foco está en la tabla.
    @objc func copy(_ sender: Any?) {
        copySelectionToClipboard()
    }

    @objc func cut(_ sender: Any?) {
        cutSelectionToClipboard()
    }

    @objc func paste(_ sender: Any?) {
        do {
            let pasted = try pasteItemsFromClipboard()
            if pasted == 0 {
                onStatus?("No hay rutas válidas para pegar.")
            }
        } catch {
            onStatus?("No se pudo pegar: \(J4FError.from(error).userMessage)")
        }
    }

    @objc func duplicate(_ sender: Any?) {
        duplicateSelection()
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
            onStatus?("No se pudo renombrar: \(J4FError.from(error).userMessage)")
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
        guard idx >= 0, idx < tabURLs.count else { return }
        if idx == activeTabIndex {
            navigateToParentDirectory()
            return
        }
        activeTabIndex = idx
        historyBack.removeAll()
        historyForward.removeAll()
        loadDirectory(tabURLs[idx], pushHistory: false)
    }

    private func refreshTabsControl() {
        tabsControl.segmentCount = tabURLs.count
        while tabCustomTitles.count < tabURLs.count {
            tabCustomTitles.append(nil)
        }
        for idx in 0..<tabURLs.count {
            let url = tabURLs[idx]
            let base = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
            let title = tabCustomTitles[idx].map { "\(idx + 1): \($0)" } ?? "\(idx + 1): \(base)"
            tabsControl.setLabel(title, forSegment: idx)
            tabsControl.setWidth(120, forSegment: idx)
        }
        tabsControl.selectedSegment = activeTabIndex
    }
}

private protocol FocusAwareTableViewDelegate: AnyObject {
    func activatePanel()
    /// v2.1 — la tabla cambió de tamaño: reajusta columnas si hace falta.
    func tableDidLayout()
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

/// v2.2c — split de los dos paneles con reparto propio.
///
/// En este contexto (NSSplitView con Auto Layout dentro del hosting de SwiftUI), ni el
/// arrastre nativo de la divisoria ni `setPosition(_:ofDividerAt:)` mueven los paneles
/// (verificado: ambas eran no-op mientras que una constraint propia al 999 sí mueve).
/// El reparto se controla aquí con dos constraints propias (`ancho0 == X` y
/// `ancho1 == total − X`, prioridad 999, por encima de las internas al 250) que se ajustan
/// arrastrando la divisoria; la proporción se guarda en `j4f.panelsLeftRatio` y se mantiene
/// al redimensionar la ventana.
private final class J4FPanelSplitView: NSSplitView {
    static let leftRatioKey = "j4f.panelsLeftRatio"
    private let minPaneWidth: CGFloat = 140
    private var pane0Width: NSLayoutConstraint?
    private var pane1Width: NSLayoutConstraint?
    private var leftRatio: CGFloat = 0.5
    private var manualWidthsEnabled = false
    private var isDraggingDivider = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        if let stored = UserDefaults.standard.object(forKey: Self.leftRatioKey) as? Double,
           stored > 0.05, stored < 0.95 {
            leftRatio = CGFloat(stored)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) no soportado")
    }

    /// Crea las constraints de reparto (llamar DESPUÉS de añadir los dos paneles).
    /// Prioridad 998: por debajo del preview del cuerpo (@999) para que al agrandar el
    /// preview sean estos paneles quienes cedan el espacio, y por encima de las internas
    /// del split (250/750) para que el reparto propio siga mandando.
    func installPaneConstraints(left: NSView, right: NSView) {
        let c0 = left.widthAnchor.constraint(equalToConstant: 283)
        c0.priority = NSLayoutConstraint.Priority(998)
        let c1 = right.widthAnchor.constraint(equalToConstant: 283)
        c1.priority = NSLayoutConstraint.Priority(998)
        pane0Width = c0
        pane1Width = c1
        setManualWidthsEnabled(true)
    }

    /// Activa/desactiva el reparto manual. En modo de un solo panel se desactiva para que el
    /// split colapse el panel oculto con sus constraints internas.
    func setManualWidthsEnabled(_ enabled: Bool) {
        manualWidthsEnabled = enabled
        pane0Width?.isActive = enabled
        pane1Width?.isActive = enabled
        if enabled {
            applyRatio()
            needsLayout = true
        }
        window?.invalidateCursorRects(for: self)
    }

    /// Aplica la proporción guardada (idempotente).
    private func applyRatio() {
        guard manualWidthsEnabled, let pane0Width, let pane1Width else { return }
        // El split reserva 1pt a cada lado de la divisoria: menos ese margen no hay conflictos.
        let total = bounds.width - dividerThickness - 1
        guard total > minPaneWidth * 2 else { return }
        let first = min(max(round(total * leftRatio), minPaneWidth), total - minPaneWidth)
        guard abs(pane0Width.constant - first) > 0.5 else { return }
        pane0Width.constant = first
        pane1Width.constant = total - first
    }

    override func layout() {
        super.layout()
        if !isDraggingDivider {
            applyRatio()
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard manualWidthsEnabled, let first = subviews.first else { return }
        let dividerX = first.frame.maxX
        addCursorRect(
            NSRect(x: dividerX - 2, y: 0, width: dividerThickness + 4, height: bounds.height),
            cursor: .resizeLeftRight
        )
    }

    private func isPointOnDivider(_ point: NSPoint) -> Bool {
        guard let first = subviews.first else { return false }
        return abs(point.x - first.frame.maxX) <= 3
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard manualWidthsEnabled, subviews.count >= 2, isPointOnDivider(point),
              let pane0 = pane0Width, let pane1 = pane1Width else {
            super.mouseDown(with: event)
            return
        }
        isDraggingDivider = true
        NSCursor.resizeLeftRight.set()
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp { break }
            let pt = convert(next.locationInWindow, from: nil)
            let total = bounds.width - dividerThickness - 1
            let first = min(max(pt.x, minPaneWidth), total - minPaneWidth)
            leftRatio = first / total
            pane0.constant = first
            pane1.constant = total - first
            layoutSubtreeIfNeeded()
        }
        isDraggingDivider = false
        UserDefaults.standard.set(Double(leftRatio), forKey: Self.leftRatioKey)
        window?.invalidateCursorRects(for: self)
    }
}

/// v2.2d — split del cuerpo (sidebar | paneles | preview) con la divisoria del **preview**
/// arrastrable: mismo problema y misma solución que en los paneles (el arrastre nativo es no-op
/// en este contexto). El ancho del preview se controla con una constraint propia (@999) y se
/// recuerda en `j4f.previewWidth`; al crecer la ventana el espacio extra va a los paneles.
private final class J4FBodySplitView: NSSplitView {
    static let previewWidthKey = "j4f.previewWidth"
    private let minPreviewWidth: CGFloat = 140
    private let minPanelsWidth: CGFloat = 220
    private let defaultPreviewWidth: CGFloat = 232
    private var previewWidthConstraint: NSLayoutConstraint?
    private var previewCapConstraint: NSLayoutConstraint?
    private var splitWidthConstraint: NSLayoutConstraint?
    private var previewWidth: CGFloat = 232
    private var isDraggingDivider = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        if let stored = UserDefaults.standard.object(forKey: Self.previewWidthKey) as? Double,
           stored >= Double(minPreviewWidth) - 1, stored <= 2000 {
            previewWidth = CGFloat(stored)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) no soportado")
    }

    /// Crea las constraints del preview (llamar DESPUÉS de añadirlo al split). Todas se
    /// ACTIVAN aquí (en viewDidLoad), nunca dentro de `layout()`: activar constraints
    /// durante un ciclo de layout provoca bucles de «Update Constraints» y aborta la app.
    func installPreviewConstraint(_ preview: NSView) {
        let c = preview.widthAnchor.constraint(equalToConstant: previewWidth)
        c.priority = NSLayoutConstraint.Priority(999)
        c.isActive = true
        previewWidthConstraint = c
        // Techo requerido del preview (contra la ventana, constante actualizada en layout()).
        let cap = preview.widthAnchor.constraint(lessThanOrEqualToConstant: 1000)
        cap.priority = .required
        cap.isActive = true
        previewCapConstraint = cap
        // Ancho fijo requerido del split (contra la ventana, constante actualizada en layout()).
        let w = widthAnchor.constraint(equalToConstant: 1700)
        w.priority = .required
        w.isActive = true
        splitWidthConstraint = w
    }

    /// Presupuesto real de anchura: la ventana (medido: el bounds del contenedor/split se
    /// infla si una subview no cede porque la cadena de vistas abraza el contenido).
    private var budgetWidth: CGFloat {
        window?.frame.width ?? superview?.bounds.width ?? bounds.width
    }

    /// Límites del preview para el ancho disponible.
    private func clampedPreviewWidth(_ width: CGFloat) -> CGFloat {
        let sidebarWidth = subviews.first?.frame.width ?? 250
        let maxWidth = max(minPreviewWidth, budgetWidth - 24 - sidebarWidth - (dividerThickness + 1) * 2 - minPanelsWidth)
        return min(max(width, minPreviewWidth), maxWidth)
    }

    /// Fija el ancho del propio split al de la VENTANA (requerido). Medido: si el split
    /// puede crecer, al agrandar el preview el solver prefiere estirar el split hacia la
    /// derecha (invisible) antes que menguar los paneles; con el ancho fijo, el espacio
    /// del preview sale de los paneles y el arrastre se ve. De paso rellena el ancho real
    /// de la ventana (antes quedaba un hueco muerto a la derecha).
    private func refreshSplitWidthIfNeeded() {
        guard let c = splitWidthConstraint else { return }
        let target = budgetWidth - 24
        if abs(c.constant - target) > 1 {
            c.constant = target
        }
    }

    /// Techo REQUERIDO del preview contra el ancho de la VENTANA: sin él, una petición
    /// grande estira toda la cadena de vistas (medido: el split llegó a 5.634pt) y el
    /// arrastre no movería la divisoria visible.
    private func refreshPreviewCapIfNeeded() {
        guard let cap = previewCapConstraint else { return }
        let maxW = max(minPreviewWidth, budgetWidth - 24 - 250 - (dividerThickness + 1) * 2 - minPanelsWidth)
        if abs(cap.constant - maxW) > 1 {
            cap.constant = maxW
        }
    }

    private func applyPreviewWidth() {
        guard let c = previewWidthConstraint else { return }
        // v2.2d — autolimpieza: si el layout no pudo conceder el ancho pedido (los
        // mínimos internos «requeridos» de los paneles son el tope real), se adopta el
        // ancho resuelto para que lo guardado coincida con lo visible y no quede un
        // valor fantasma tras reiniciar.
        if let actual = subviews.last?.frame.width, actual > minPreviewWidth,
           abs(actual - previewWidth) > 1 {
            previewWidth = actual
            UserDefaults.standard.set(Double(actual), forKey: Self.previewWidthKey)
        }
        let target = clampedPreviewWidth(previewWidth)
        guard abs(c.constant - target) > 0.5 else { return }
        c.constant = target
        window?.invalidateCursorRects(for: self)
    }

    override func layout() {
        super.layout()
        refreshSplitWidthIfNeeded()
        refreshPreviewCapIfNeeded()
        if !isDraggingDivider {
            applyPreviewWidth()
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard subviews.count >= 2 else { return }
        let dividerX = subviews[1].frame.maxX
        addCursorRect(
            NSRect(x: dividerX - 2, y: 0, width: dividerThickness + 4, height: bounds.height),
            cursor: .resizeLeftRight
        )
    }

    private func isPointOnPreviewDivider(_ point: NSPoint) -> Bool {
        guard subviews.count >= 2 else { return false }
        return abs(point.x - subviews[1].frame.maxX) <= 3
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard subviews.count >= 2, isPointOnPreviewDivider(point),
              let previewWidthConstraint else {
            super.mouseDown(with: event)
            return
        }
        isDraggingDivider = true
        NSCursor.resizeLeftRight.set()
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp { break }
            // Candidato medido desde el borde derecho real de la ventana (no contra el
            // bounds del split: puede estar inflado).
            let lw = next.locationInWindow
            let candidate = budgetWidth - 14 - lw.x
            let width = clampedPreviewWidth(candidate)
            previewWidth = width
            previewWidthConstraint.constant = width
            layoutSubtreeIfNeeded()
        }
        isDraggingDivider = false
        // Se guarda el ancho REAL resuelto (si los paneles no dieron más, el tope real),
        // no la última demanda del puntero.
        let resolved = subviews.last?.frame.width ?? previewWidth
        previewWidth = resolved
        UserDefaults.standard.set(Double(resolved), forKey: Self.previewWidthKey)
        window?.invalidateCursorRects(for: self)
    }
}

private final class FocusAwareTableView: NSTableView {
    weak var focusDelegate: FocusAwareTableViewDelegate?
    var onEnterPressed: (() -> Void)?
    var onBackgroundClicked: (() -> Void)?

    override func layout() {
        super.layout()
        focusDelegate?.tableDidLayout()
    }

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

extension FilePanelViewController: FocusAwareTableViewDelegate {
    func tableDidLayout() {
        fitColumnsIfNeeded()
        scheduleSettledColumnRefit()
    }
}

/// v2.1.1 — cabecera con gesto de Finder: doble clic en el divisor de una columna la ajusta
/// al contenido (el resto del comportamiento es el estándar). Además distingue el ARRASTRE
/// real de un divisor: solo entonces los anchos pasan a considerarse «del usuario» (antes
/// cualquier cambio programático los marcaba y los transitorios del arranque quedaban fijados).
private final class J4FFittingHeaderView: NSTableHeaderView {
    weak var ownerPanel: FilePanelViewController?

    override func mouseDown(with event: NSEvent) {
        guard let table = tableView else {
            super.mouseDown(with: event)
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        var dividerIndex: Int?
        for (index, column) in table.tableColumns.enumerated() where !column.isHidden {
            if abs(point.x - headerRect(ofColumn: index).maxX) <= 5 {
                dividerIndex = index
                break
            }
        }
        if event.clickCount == 2, let dividerIndex {
            let column = table.tableColumns[dividerIndex]
            column.sizeToFit()
            table.reloadData()
            ownerPanel?.markColumnsAdjustedByUser()
            return
        }
        super.mouseDown(with: event)
        if dividerIndex != nil {
            // El arrastre terminó (super.mouseDown bloquea hasta el mouseUp).
            ownerPanel?.markColumnsAdjustedByUser()
        }
    }
}
