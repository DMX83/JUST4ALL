import AppKit

/// v2.3 (Panel Hub, fase F1) — Módulo «DESK mini» del panel lateral.
///
/// Reutiliza los motores que ya viven en JUST4FOLDERS (no reescribe nada):
/// - **Buscador**: consulta el índice FTS5 global vía `IndexedSearchService` (el mismo de ⌘F);
///   el commander lanza la búsqueda y devuelve los resultados con `presentSearchResults`.
/// - **Bandeja**: carpeta de descargas con sus últimos elementos y acceso directo a
///   «Ordenar…», que reutiliza la ventana de ordenación (plan + journal + Deshacer + IA opcional).
///
/// Guardrails heredados del flujo de ordenación: solo se MUEVE (nunca se borra), dudosos →
/// 99_SinClasificar y la IA es opcional y no bloquea.
final class DeskMiniPanelView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {

    // MARK: - Callbacks (los cablea el commander)

    /// Abrir una carpeta en el panel activo (o un fichero con su app por defecto).
    var onOpenURL: ((URL) -> Void)?
    /// Abrir la ventana de ordenación para una carpeta (clasificar + mover con diario).
    var onOrderFolder: ((URL) -> Void)?
    /// Lanzar la búsqueda global del índice; los resultados llegan por `presentSearchResults`.
    var searchProvider: ((String) -> Void)?

    /// Carpeta de la bandeja (por defecto, Descargas del usuario).
    let inboxURL: URL

    // MARK: - Subvistas

    private let searchField = NSSearchField()
    private let searchStatus = NSTextField(labelWithString: "")
    private let resultsTable = NSTableView()
    private let resultsScroll = NSScrollView()
    private let inboxHeader = NSTextField(labelWithString: "")
    private let inboxTable = NSTableView()
    private let inboxScroll = NSScrollView()
    private let orderButton = NSButton()
    private let openInboxButton = NSButton()
    private let refreshButton = NSButton()
    // F2 — cola «por revisar» y actividad en curso.
    private let reviewLabel = NSTextField(labelWithString: "")
    private let reviewButton = NSButton()
    private var reviewFolder: URL?
    private let activityLabel = NSTextField(labelWithString: "")
    private let activityBar = NSProgressIndicator()

    // MARK: - Datos

    private struct InboxItem {
        let url: URL
        let modified: Date?
        let isDirectory: Bool
    }

    private var results: [IndexedSearchService.Hit] = []
    private var inboxItems: [InboxItem] = []
    private var pendingSearch: DispatchWorkItem?
    private var lastSearchQuery = ""
    private let cellID = NSUserInterfaceItemIdentifier("j4f.deskMini.cell")

    private static let ageFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.unitsStyle = .short
        return formatter
    }()

    // MARK: - Init

    init(inboxURL: URL) {
        self.inboxURL = inboxURL
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        buildUI()
        refreshInbox()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) no soportado")
    }

    // MARK: - Construcción

    private func buildUI() {
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "Buscar en todo el índice…"
        searchField.controlSize = .small
        searchField.delegate = self
        searchField.setAccessibilityLabel("Buscador del índice (módulo DESK)")

        searchStatus.translatesAutoresizingMaskIntoConstraints = false
        searchStatus.font = .systemFont(ofSize: 10.5)
        searchStatus.textColor = .tertiaryLabelColor
        searchStatus.lineBreakMode = .byTruncatingTail

        configure(table: resultsTable, rowHeight: 34, label: "Resultados del índice")
        configure(scroll: resultsScroll, document: resultsTable)

        inboxHeader.translatesAutoresizingMaskIntoConstraints = false
        inboxHeader.font = .systemFont(ofSize: 10.5, weight: .semibold)
        inboxHeader.textColor = .secondaryLabelColor
        inboxHeader.lineBreakMode = .byTruncatingMiddle

        configure(table: inboxTable, rowHeight: 34, label: "Bandeja de descargas")
        configure(scroll: inboxScroll, document: inboxTable)

        // F2 — «por revisar»: dudosos de 99_SinClasificar del último destino de ordenación.
        reviewLabel.translatesAutoresizingMaskIntoConstraints = false
        reviewLabel.font = .systemFont(ofSize: 10.5, weight: .semibold)
        reviewLabel.textColor = .secondaryLabelColor
        reviewLabel.lineBreakMode = .byTruncatingMiddle
        reviewLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        reviewButton.translatesAutoresizingMaskIntoConstraints = false
        reviewButton.title = "Ver en panel"
        reviewButton.bezelStyle = .rounded
        reviewButton.controlSize = .small
        reviewButton.isHidden = true
        reviewButton.target = self
        reviewButton.action = #selector(onReviewClicked)
        reviewButton.toolTip = "Abre 99_SinClasificar en el panel de ficheros para revisarlo"

        let reviewRow = NSStackView(views: [reviewLabel, reviewButton])
        reviewRow.orientation = .horizontal
        reviewRow.spacing = 6
        reviewRow.translatesAutoresizingMaskIntoConstraints = false

        // F2 — actividad: mismos datos que la barra inferior del commander (trabajo en curso).
        activityLabel.translatesAutoresizingMaskIntoConstraints = false
        activityLabel.font = .systemFont(ofSize: 10.5)
        activityLabel.textColor = .tertiaryLabelColor
        activityLabel.lineBreakMode = .byTruncatingMiddle
        activityLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        activityBar.translatesAutoresizingMaskIntoConstraints = false
        activityBar.style = .bar
        activityBar.isIndeterminate = false
        activityBar.minValue = 0
        activityBar.maxValue = 1
        activityBar.controlSize = .small
        activityBar.isHidden = true

        let activityRow = NSStackView(views: [activityLabel, activityBar])
        activityRow.orientation = .horizontal
        activityRow.spacing = 6
        activityRow.translatesAutoresizingMaskIntoConstraints = false
        activityBar.widthAnchor.constraint(greaterThanOrEqualToConstant: 80).isActive = true

        orderButton.translatesAutoresizingMaskIntoConstraints = false
        orderButton.title = "Ordenar…"
        orderButton.bezelStyle = .rounded
        orderButton.controlSize = .small
        orderButton.target = self
        orderButton.action = #selector(onOrderClicked)
        orderButton.toolTip = "Clasifica y mueve lo que hay en la bandeja (con diario y Deshacer; nunca borra)"

        openInboxButton.translatesAutoresizingMaskIntoConstraints = false
        openInboxButton.title = "Abrir en panel"
        openInboxButton.bezelStyle = .rounded
        openInboxButton.controlSize = .small
        openInboxButton.target = self
        openInboxButton.action = #selector(onOpenInboxClicked)
        openInboxButton.toolTip = "Abre la bandeja en el panel de ficheros activo"

        refreshButton.translatesAutoresizingMaskIntoConstraints = false
        refreshButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Actualizar bandeja")
        refreshButton.bezelStyle = .rounded
        refreshButton.controlSize = .small
        refreshButton.target = self
        refreshButton.action = #selector(onRefreshClicked)
        refreshButton.toolTip = "Volver a leer la bandeja"

        let buttonRow = NSStackView(views: [orderButton, openInboxButton, refreshButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 6
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        addSubview(searchField)
        addSubview(searchStatus)
        addSubview(resultsScroll)
        addSubview(reviewRow)
        addSubview(inboxHeader)
        addSubview(inboxScroll)
        addSubview(activityRow)
        addSubview(buttonRow)

        resultsTable.menu = makeContextMenu(for: resultsTable)
        inboxTable.menu = makeContextMenu(for: inboxTable)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: topAnchor),
            searchField.leadingAnchor.constraint(equalTo: leadingAnchor),
            searchField.trailingAnchor.constraint(equalTo: trailingAnchor),

            searchStatus.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 3),
            searchStatus.leadingAnchor.constraint(equalTo: leadingAnchor),
            searchStatus.trailingAnchor.constraint(equalTo: trailingAnchor),

            resultsScroll.topAnchor.constraint(equalTo: searchStatus.bottomAnchor, constant: 4),
            resultsScroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            resultsScroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            resultsScroll.bottomAnchor.constraint(equalTo: reviewRow.topAnchor, constant: -8),
            resultsScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 60),

            reviewRow.leadingAnchor.constraint(equalTo: leadingAnchor),
            reviewRow.trailingAnchor.constraint(equalTo: trailingAnchor),

            inboxHeader.topAnchor.constraint(equalTo: reviewRow.bottomAnchor, constant: 8),
            inboxHeader.leadingAnchor.constraint(equalTo: leadingAnchor),
            inboxHeader.trailingAnchor.constraint(equalTo: trailingAnchor),

            inboxScroll.topAnchor.constraint(equalTo: inboxHeader.bottomAnchor, constant: 4),
            inboxScroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            inboxScroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            inboxScroll.heightAnchor.constraint(equalToConstant: 150),

            activityRow.topAnchor.constraint(equalTo: inboxScroll.bottomAnchor, constant: 4),
            activityRow.leadingAnchor.constraint(equalTo: leadingAnchor),
            activityRow.trailingAnchor.constraint(equalTo: trailingAnchor),

            buttonRow.topAnchor.constraint(equalTo: activityRow.bottomAnchor, constant: 6),
            buttonRow.leadingAnchor.constraint(equalTo: leadingAnchor),
            buttonRow.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        setSearchStatusIdle()
        updateInboxHeader()
        updateReview(count: 0, folderName: nil, folder: nil)
        updateActivity(text: nil, progress: nil)
    }

    private func configure(table: NSTableView, rowHeight: CGFloat, label: String) {
        table.headerView = nil
        table.rowHeight = rowHeight
        table.usesAlternatingRowBackgroundColors = false
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .regular
        table.allowsMultipleSelection = false
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(onTableDoubleClick)
        table.setAccessibilityLabel(label)
        if table.tableColumns.isEmpty {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
            column.width = 200
            table.addTableColumn(column)
        }
    }

    private func configure(scroll: NSScrollView, document: NSTableView) {
        scroll.documentView = document
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
    }

    // MARK: - Búsqueda (el commander ejecuta la consulta)

    func controlTextDidChange(_ obj: Notification) {
        guard (obj.object as? NSSearchField) === searchField else { return }
        pendingSearch?.cancel()
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        lastSearchQuery = query
        guard !query.isEmpty else {
            results = []
            resultsTable.reloadData()
            setSearchStatusIdle()
            return
        }
        searchStatus.stringValue = "Buscando «\(query)»…"
        let work = DispatchWorkItem { [weak self] in
            self?.searchProvider?(query)
        }
        pendingSearch = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    /// Enter abre el primer resultado; Esc limpia el buscador.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard control === searchField else { return false }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            if let first = results.first {
                onOpenURL?(URL(fileURLWithPath: first.path))
            } else if !searchField.stringValue.isEmpty {
                NSSound.beep()
            }
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            pendingSearch?.cancel()
            searchField.stringValue = ""
            lastSearchQuery = ""
            results = []
            resultsTable.reloadData()
            setSearchStatusIdle()
            return true
        }
        return false
    }

    /// Llamado por el commander con los resultados de la búsqueda global.
    func presentSearchResults(_ hits: [IndexedSearchService.Hit], for query: String) {
        guard query == lastSearchQuery else { return } // respuesta de una consulta anterior
        results = Array(hits.prefix(300))
        resultsTable.reloadData()
        searchStatus.stringValue = results.isEmpty
            ? "Sin resultados para «\(query)»."
            : "\(hits.count) resultado(s) — doble clic para abrir."
    }

    private func setSearchStatusIdle() {
        searchStatus.stringValue = "Escribe para buscar en todo el índice (lo mismo que ⌘F)."
    }

    // MARK: - Bandeja

    func refreshInbox() {
        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey]
        let contents = (try? fileManager.contentsOfDirectory(
            at: inboxURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )) ?? []
        var items: [InboxItem] = []
        items.reserveCapacity(contents.count)
        for url in contents {
            let values = try? url.resourceValues(forKeys: Set(keys))
            items.append(InboxItem(
                url: url,
                modified: values?.contentModificationDate,
                isDirectory: values?.isDirectory ?? false
            ))
        }
        items.sort { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }
        inboxItems = Array(items.prefix(14))
        inboxTable.reloadData()
        updateInboxHeader()
        orderButton.isEnabled = !inboxItems.isEmpty
    }

    private func updateInboxHeader() {
        inboxHeader.stringValue = "BANDEJA · \(inboxURL.lastPathComponent.uppercased()) (\(inboxItems.count))"
    }

    // MARK: - Colas F2 (revisión + actividad)

    /// Foco directo al buscador (el commander lo pide al cambiar al módulo).
    func focusSearch() {
        window?.makeFirstResponder(searchField)
    }

    /// Actualiza la cola «por revisar» (dudosos de 99_SinClasificar del último destino).
    func updateReview(count: Int, folderName: String?, folder: URL?) {
        reviewFolder = folder
        reviewButton.isHidden = folder == nil
        if let folderName {
            reviewLabel.stringValue = count == 0
                ? "POR REVISAR · nada pendiente en \(folderName) ✓"
                : "POR REVISAR · \(count) en \(folderName)"
        } else {
            reviewLabel.stringValue = "POR REVISAR · aún sin ordenaciones (aquí aparecerán los dudosos)"
        }
    }

    /// Actividad en curso (mismos datos que la barra inferior del commander).
    func updateActivity(text: String?, progress: Double?) {
        if let text, !text.isEmpty {
            activityLabel.stringValue = "ACTIVIDAD · \(text)"
        } else {
            activityLabel.stringValue = "ACTIVIDAD · sin trabajos en curso"
        }
        if let progress {
            activityBar.isHidden = false
            activityBar.doubleValue = max(0, min(1, progress))
        } else {
            activityBar.isHidden = true
        }
    }

    @objc private func onReviewClicked() {
        if let reviewFolder {
            onOpenURL?(reviewFolder)
        }
    }

    // MARK: - Menús contextuales

    private func makeContextMenu(for table: NSTableView) -> NSMenu {
        let menu = NSMenu()
        let open = NSMenuItem(title: "Abrir", action: #selector(menuOpen(_:)), keyEquivalent: "")
        open.target = self
        open.representedObject = table
        let parent = NSMenuItem(title: "Abrir la carpeta contenedora", action: #selector(menuOpenParent(_:)), keyEquivalent: "")
        parent.target = self
        parent.representedObject = table
        menu.addItem(open)
        menu.addItem(parent)
        if table === inboxTable {
            menu.addItem(.separator())
            let order = NSMenuItem(title: "Ordenar la bandeja…", action: #selector(menuOrderInbox(_:)), keyEquivalent: "")
            order.target = self
            menu.addItem(order)
        }
        return menu
    }

    private func url(forRow row: Int, in table: NSTableView) -> URL? {
        if table === resultsTable, row >= 0, row < results.count {
            return URL(fileURLWithPath: results[row].path)
        }
        if table === inboxTable, row >= 0, row < inboxItems.count {
            return inboxItems[row].url
        }
        return nil
    }

    @objc private func menuOpen(_ sender: NSMenuItem) {
        guard let table = sender.representedObject as? NSTableView,
              let url = url(forRow: table.clickedRow, in: table) else { return }
        onOpenURL?(url)
    }

    @objc private func menuOpenParent(_ sender: NSMenuItem) {
        guard let table = sender.representedObject as? NSTableView,
              let url = url(forRow: table.clickedRow, in: table) else { return }
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        onOpenURL?(isDirectory.boolValue ? url : url.deletingLastPathComponent())
    }

    @objc private func menuOrderInbox(_ sender: NSMenuItem) {
        onOrderFolder?(inboxURL)
    }

    // MARK: - Acciones

    @objc private func onTableDoubleClick() {
        if resultsTable.clickedRow >= 0, resultsTable.clickedRow < results.count {
            onOpenURL?(URL(fileURLWithPath: results[resultsTable.clickedRow].path))
        } else if inboxTable.clickedRow >= 0, inboxTable.clickedRow < inboxItems.count {
            onOpenURL?(inboxItems[inboxTable.clickedRow].url)
        }
    }

    @objc private func onOrderClicked() {
        onOrderFolder?(inboxURL)
    }

    @objc private func onOpenInboxClicked() {
        onOpenURL?(inboxURL)
    }

    @objc private func onRefreshClicked() {
        refreshInbox()
    }

    // MARK: - Tablas

    func numberOfRows(in tableView: NSTableView) -> Int {
        tableView === resultsTable ? results.count : inboxItems.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: cellID, owner: self) as? NSTableCellView {
            cell = reused
        } else {
            cell = makeCell()
            cell.identifier = cellID
        }
        let subtitle = cell.viewWithTag(99) as? NSTextField

        if tableView === resultsTable, row < results.count {
            let hit = results[row]
            cell.imageView?.image = NSWorkspace.shared.icon(forFile: hit.path)
            cell.textField?.stringValue = hit.name
            subtitle?.stringValue = Self.prettyParent(of: hit.path)
        } else if row < inboxItems.count {
            let item = inboxItems[row]
            cell.imageView?.image = NSWorkspace.shared.icon(forFile: item.url.path)
            cell.textField?.stringValue = item.url.lastPathComponent
            var caption = Self.prettyAge(item.modified)
            if item.isDirectory { caption += caption.isEmpty ? "carpeta" : " · carpeta" }
            subtitle?.stringValue = caption
        }
        return cell
    }

    private func makeCell() -> NSTableCellView {
        let cell = NSTableCellView()

        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.imageScaling = .scaleProportionallyDown

        let name = NSTextField(labelWithString: "")
        name.translatesAutoresizingMaskIntoConstraints = false
        name.font = .systemFont(ofSize: 12)
        name.lineBreakMode = .byTruncatingMiddle

        let subtitle = NSTextField(labelWithString: "")
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        subtitle.tag = 99
        subtitle.font = .systemFont(ofSize: 10.5)
        subtitle.textColor = .tertiaryLabelColor
        subtitle.lineBreakMode = .byTruncatingMiddle

        cell.addSubview(icon)
        cell.addSubview(name)
        cell.addSubview(subtitle)
        cell.textField = name
        cell.imageView = icon

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),

            name.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            name.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -2),
            name.topAnchor.constraint(equalTo: cell.topAnchor, constant: 3),

            subtitle.leadingAnchor.constraint(equalTo: name.leadingAnchor),
            subtitle.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -2),
            subtitle.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 1)
        ])
        return cell
    }

    // MARK: - Formato

    private static func prettyParent(of path: String) -> String {
        let parent = (path as NSString).deletingLastPathComponent
        return (parent as NSString).abbreviatingWithTildeInPath
    }

    private static func prettyAge(_ date: Date?) -> String {
        guard let date else { return "" }
        return ageFormatter.localizedString(for: date, relativeTo: Date())
    }
}
