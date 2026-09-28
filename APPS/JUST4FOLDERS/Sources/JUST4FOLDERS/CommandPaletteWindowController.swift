import AppKit
import Foundation

/// Ola 3 — Paleta de comandos (⌘K): busca y ejecuta acciones del commander.
/// Teclado primero: escribir filtra, ↑/↓ navegan, Enter ejecuta, Esc cierra.
final class CommandPaletteWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSControlTextEditingDelegate {
    struct Command {
        let title: String
        let hint: String
        let run: () -> Void
    }

    private let commands: [Command]
    private var filtered: [Command] = []
    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    var onClose: (() -> Void)?

    init(commands: [Command]) {
        self.commands = commands
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 380),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Comandos"
        panel.isReleasedWhenClosed = false
        super.init(window: panel)
        buildUI()
        filter("")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) no soportado")
    }

    func present() {
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(searchField)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        searchField.placeholderString = "Buscar comando…  (↑/↓ y Enter)"
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.font = .systemFont(ofSize: 13)

        let titleColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
        titleColumn.title = "Comando"
        titleColumn.width = 360
        let hintColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("hint"))
        hintColumn.title = "Teclas"
        hintColumn.width = 120
        tableView.addTableColumn(titleColumn)
        tableView.addTableColumn(hintColumn)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 22
        tableView.doubleAction = #selector(runSelected)
        tableView.target = self

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        content.addSubview(searchField)
        content.addSubview(scrollView)
        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            searchField.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),

            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12)
        ])
    }

    private func filter(_ text: String) {
        let needle = Self.fold(text.trimmingCharacters(in: .whitespacesAndNewlines))
        filtered = needle.isEmpty ? commands : commands.filter { Self.fold($0.title).contains(needle) }
        tableView.reloadData()
        if !filtered.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        filter(searchField.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)):
            move(by: -1)
            return true
        case #selector(NSResponder.moveDown(_:)):
            move(by: 1)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            runSelected()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            close()
            return true
        default:
            return false
        }
    }

    private func move(by delta: Int) {
        guard !filtered.isEmpty else { return }
        let current = max(0, tableView.selectedRow)
        let next = max(0, min(filtered.count - 1, current + delta))
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }

    @objc private func runSelected() {
        let row = tableView.selectedRow
        guard row >= 0, row < filtered.count else { return }
        let command = filtered[row]
        close()
        command.run()
    }

    // MARK: - Tabla

    func numberOfRows(in tableView: NSTableView) -> Int {
        filtered.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < filtered.count else { return nil }
        let command = filtered[row]
        let columnId = tableColumn?.identifier.rawValue ?? "title"
        let text = columnId == "title" ? command.title : command.hint

        let identifier = NSUserInterfaceItemIdentifier("PaletteCell-\(columnId)")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = identifier
        let label: NSTextField
        if let existing = cell.textField {
            label = existing
        } else {
            label = NSTextField(labelWithString: "")
            label.translatesAutoresizingMaskIntoConstraints = false
            label.lineBreakMode = .byTruncatingTail
            cell.textField = label
            cell.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }
        label.stringValue = text
        label.font = .systemFont(ofSize: 12)
        label.textColor = columnId == "title" ? .labelColor : .secondaryLabelColor
        return cell
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "es_ES"))
    }
}
