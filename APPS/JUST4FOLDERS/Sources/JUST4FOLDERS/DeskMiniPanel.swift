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
        addSubview(inboxHeader)
        addSubview(inboxScroll)
        addSubview(buttonRow)

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
            resultsScroll.bottomAnchor.constraint(equalTo: inboxHeader.topAnchor, constant: -10),
            resultsScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 60),

            inboxHeader.leadingAnchor.constraint(equalTo: leadingAnchor),
            inboxHeader.trailingAnchor.constraint(equalTo: trailingAnchor),

            inboxScroll.topAnchor.constraint(equalTo: inboxHeader.bottomAnchor, constant: 4),
            inboxScroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            inboxScroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            inboxScroll.heightAnchor.constraint(equalToConstant: 150),

            buttonRow.topAnchor.constraint(equalTo: inboxScroll.bottomAnchor, constant: 6),
            buttonRow.leadingAnchor.constraint(equalTo: leadingAnchor),
            buttonRow.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        setSearchStatusIdle()
        updateInboxHeader()
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
