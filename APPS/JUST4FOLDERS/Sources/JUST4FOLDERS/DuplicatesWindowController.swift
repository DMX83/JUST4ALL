import AppKit
import Foundation
import J4FOps

/// v1.2 — Ventana de duplicados: grupos por tamaño + SHA-256, revelar en Finder y mover
/// a la Papelera con confirmación (nunca borrado permanente).
final class DuplicatesWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let root: URL
    private let onClosed: () -> Void

    private let tableView = NSTableView()
    private let summaryLabel = NSTextField(labelWithString: "Analizando…")
    private let trashButton = NSButton(title: "Mover a la Papelera seleccionados", target: nil, action: nil)
    private let revealButton = NSButton(title: "Revelar en Finder", target: nil, action: nil)

    private enum Row {
        case header(size: Int64, count: Int)
        case file(URL, Int64)

        var isFile: Bool {
            if case .file = self { return true }
            return false
        }

        var url: URL? {
            if case .file(let url, _) = self { return url }
            return nil
        }
    }

    private var rows: [Row] = []
    private var scanTask: Task<Void, Never>?
    private var didNotifyClosed = false

    init(root: URL, onClosed: @escaping () -> Void) {
        self.root = root
        self.onClosed = onClosed
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        let name = root.lastPathComponent.isEmpty ? root.path : root.lastPathComponent
        panel.title = "Duplicados — \(name)"
        panel.isReleasedWhenClosed = false
        super.init(window: panel)
        buildUI()
        startScan()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) no soportado")
    }

    func windowWillClose(_ notification: Notification) {
        scanTask?.cancel()
        if !didNotifyClosed {
            didNotifyClosed = true
            onClosed()
        }
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        summaryLabel.font = .systemFont(ofSize: 12)
        summaryLabel.textColor = .secondaryLabelColor
        summaryLabel.lineBreakMode = .byTruncatingMiddle
        summaryLabel.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item"))
        column.title = "Elemento"
        column.width = 520
        let sizeColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("size"))
        sizeColumn.title = "Tamaño"
        sizeColumn.width = 90
        tableView.addTableColumn(column)
        tableView.addTableColumn(sizeColumn)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.allowsMultipleSelection = true
        tableView.usesAlternatingRowBackgroundColors = true

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let sparesButton = NSButton(title: "Seleccionar sobrantes", target: self, action: #selector(selectSpares))
        sparesButton.toolTip = "Selecciona todas las copias menos la primera de cada grupo"
        revealButton.target = self
        revealButton.action = #selector(revealSelected)
        trashButton.target = self
        trashButton.action = #selector(trashSelected)
        let closeButton = NSButton(title: "Cerrar", target: self, action: #selector(closeAction))
        closeButton.keyEquivalent = "\u{1b}"

        let buttonsRow = NSStackView(views: [sparesButton, revealButton, NSView(), trashButton, closeButton])
        buttonsRow.orientation = .horizontal
        buttonsRow.spacing = 8
        buttonsRow.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(summaryLabel)
        content.addSubview(scrollView)
        content.addSubview(buttonsRow)

        NSLayoutConstraint.activate([
            summaryLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            summaryLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            summaryLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),

            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            scrollView.topAnchor.constraint(equalTo: summaryLabel.bottomAnchor, constant: 8),
            scrollView.bottomAnchor.constraint(equalTo: buttonsRow.topAnchor, constant: -10),

            buttonsRow.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            buttonsRow.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            buttonsRow.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12)
        ])

        updateButtons()
    }

    private func startScan() {
        summaryLabel.stringValue = "Analizando \(root.path)…"
        scanTask = Task { [weak self] in
            guard let self else { return }
            do {
                let groups = try await DuplicateScanner.find(in: self.root, includeHidden: false)
                await MainActor.run { self.apply(groups: groups) }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run { self.summaryLabel.stringValue = "Error: \(error.localizedDescription)" }
            }
        }
    }

    private func apply(groups: [DuplicateScanner.Group]) {
        rows.removeAll(keepingCapacity: true)
        for group in groups {
            rows.append(.header(size: group.sizeBytes, count: group.files.count))
            for file in group.files {
                rows.append(.file(file, group.sizeBytes))
            }
        }
        tableView.reloadData()
        let wasted = groups.reduce(Int64(0)) { $0 + $1.wastedBytes }
        let files = groups.reduce(0) { $0 + $1.files.count }
        summaryLabel.stringValue = groups.isEmpty
            ? "Sin duplicados en \(root.path)"
            : "\(groups.count) grupo(s) · \(files) fichero(s) · \(ByteCountFormatter.string(fromByteCount: wasted, countStyle: .file)) recuperables"
    }

    @objc private func closeAction() {
        close()
    }

    @objc private func selectSpares() {
        var indexes = IndexSet()
        var index = 0
        while index < rows.count {
            if case .header = rows[index] {
                let start = index + 1
                var end = start
                while end < rows.count, rows[end].isFile { end += 1 }
                if end - start >= 2 {
                    indexes.insert(integersIn: (start + 1)..<end)
                }
                index = end
            } else {
                index += 1
            }
        }
        tableView.selectRowIndexes(indexes, byExtendingSelection: false)
        updateButtons()
    }

    @objc private func revealSelected() {
        let urls = tableView.selectedRowIndexes.compactMap { $0 < rows.count ? rows[$0].url : nil }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    @objc private func trashSelected() {
        let selected = tableView.selectedRowIndexes.compactMap { $0 < rows.count ? rows[$0].url : nil }
        guard !selected.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = "¿Mover \(selected.count) elemento(s) a la Papelera?"
        var list = selected.prefix(8).map { $0.lastPathComponent }.joined(separator: "\n")
        if selected.count > 8 { list += "\n…" }
        alert.informativeText = list
        alert.addButton(withTitle: "Mover a la Papelera")
        alert.addButton(withTitle: "Cancelar")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        var trashed = Set<String>()
        var failures: [String] = []
        for url in selected {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                trashed.insert(url.standardizedFileURL.path)
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        rows.removeAll { row in
            if case .file(let url, _) = row {
                return trashed.contains(url.standardizedFileURL.path)
            }
            return false
        }
        pruneSingletonGroups()
        tableView.reloadData()
        updateButtons()

        let wasted = trashed.count > 0 ? "\(trashed.count) movido(s) a la Papelera." : "Nada movido."
        summaryLabel.stringValue = failures.isEmpty ? wasted : "\(wasted) \(failures.count) fallo(s)."
    }

    /// Quita grupos que ya no tienen 2+ copias tras los borrados.
    private func pruneSingletonGroups() {
        var pruned: [Row] = []
        var index = 0
        while index < rows.count {
            if case .header = rows[index] {
                let start = index + 1
                var end = start
                while end < rows.count, rows[end].isFile { end += 1 }
                if end - start >= 2 {
                    pruned.append(contentsOf: rows[index..<end])
                }
                index = end
            } else {
                index += 1
            }
        }
        rows = pruned
    }

    private func updateButtons() {
        let hasFiles = !tableView.selectedRowIndexes.isEmpty
        revealButton.isEnabled = hasFiles
        trashButton.isEnabled = hasFiles
    }

    // MARK: - Tabla

    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        row < rows.count && rows[row].isFile
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateButtons()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < rows.count else { return nil }
        let item = rows[row]
        let columnId = tableColumn?.identifier.rawValue ?? "item"

        let text: String
        var color: NSColor = .labelColor
        var bold = false
        switch item {
        case .header(let size, let count):
            if columnId == "item" {
                text = "\(count) copias idénticas"
                bold = true
            } else {
                text = ""
            }
            color = .secondaryLabelColor
            _ = size
        case .file(let url, let size):
            if columnId == "item" {
                let base = root.standardizedFileURL.path
                let path = url.standardizedFileURL.path
                text = path.hasPrefix(base + "/") ? String(path.dropFirst(base.count + 1)) : path
            } else {
                text = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
            }
        }

        let identifier = NSUserInterfaceItemIdentifier("DupCell-\(columnId)")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = identifier
        let label: NSTextField
        if let existing = cell.textField {
            label = existing
        } else {
            label = NSTextField(labelWithString: "")
            label.translatesAutoresizingMaskIntoConstraints = false
            label.lineBreakMode = .byTruncatingMiddle
            cell.textField = label
            cell.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }
        label.stringValue = text
        label.textColor = color
        label.font = bold ? .boldSystemFont(ofSize: 11) : .systemFont(ofSize: 11)
        return cell
    }
}
