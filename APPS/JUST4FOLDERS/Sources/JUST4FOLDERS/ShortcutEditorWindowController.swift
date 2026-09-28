import AppKit
import Foundation
import J4FOps

/// v2.0 — Editor de atajos configurables: lista los comandos del monitor, permite reasignar
/// («Cambiar…» y pulsa la combinación), restablecer todo y abrir el JSON en el Finder.
final class ShortcutEditorWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let tableView = NSTableView()
    private let statusLabel = NSTextField(labelWithString: "")
    private var captureMonitor: Any?
    private var capturingCommand: String?

    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 430),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Atajos"
        panel.isReleasedWhenClosed = false
        super.init(window: panel)
        buildUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) no soportado")
    }

    func windowWillClose(_ notification: Notification) {
        if let captureMonitor {
            NSEvent.removeMonitor(captureMonitor)
        }
        captureMonitor = nil
        capturingCommand = nil
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let commandColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("command"))
        commandColumn.title = "Comando"
        commandColumn.width = 300
        let keysColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("keys"))
        keysColumn.title = "Atajo"
        keysColumn.width = 140
        tableView.addTableColumn(commandColumn)
        tableView.addTableColumn(keysColumn)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 22
        tableView.doubleAction = #selector(changeShortcut)
        tableView.target = self

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        let changeButton = NSButton(title: "Cambiar…", target: self, action: #selector(changeShortcut))
        let resetButton = NSButton(title: "Restablecer todo", target: self, action: #selector(resetAll))
        let revealButton = NSButton(title: "Abrir JSON", target: self, action: #selector(revealJSON))
        let closeButton = NSButton(title: "Cerrar", target: self, action: #selector(closeAction))
        closeButton.keyEquivalent = "\u{1b}"
        let buttonsRow = NSStackView(views: [changeButton, resetButton, revealButton, NSView(), closeButton])
        buttonsRow.orientation = .horizontal
        buttonsRow.spacing = 8
        buttonsRow.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(scrollView)
        content.addSubview(statusLabel)
        content.addSubview(buttonsRow)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            scrollView.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            scrollView.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -8),

            statusLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            statusLabel.bottomAnchor.constraint(equalTo: buttonsRow.topAnchor, constant: -6),

            buttonsRow.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            buttonsRow.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            buttonsRow.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12)
        ])
        statusLabel.stringValue = "Los menús conservan sus teclas; aquí se editan los comandos del panel."
    }

    @objc private func changeShortcut() {
        let row = tableView.selectedRow
        let commands = ShortcutStore.shared.all()
        guard row >= 0, row < commands.count else { return }
        capturingCommand = commands[row].command
        statusLabel.stringValue = "Pulsa la nueva combinación para «\(ShortcutStore.displayNames[commands[row].command] ?? commands[row].command)»… (Esc cancela)"

        captureMonitor.map(NSEvent.removeMonitor)
        captureMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { // Esc — cancelar
                self.finishCapture()
                return nil
            }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard let command = self.capturingCommand else { return event }
            let binding = ShortcutBinding(
                command: command,
                keyCode: event.keyCode,
                cmd: flags.contains(.command),
                opt: flags.contains(.option),
                shift: flags.contains(.shift),
                ctrl: flags.contains(.control)
            )
            ShortcutStore.shared.set(binding)
            self.finishCapture()
            return nil
        }
    }

    private func finishCapture() {
        if let captureMonitor {
            NSEvent.removeMonitor(captureMonitor)
        }
        captureMonitor = nil
        capturingCommand = nil
        tableView.reloadData()
        statusLabel.stringValue = "Atajo actualizado. (Esc canceló si no pulsaste ninguna combinación.)"
    }

    @objc private func resetAll() {
        ShortcutStore.shared.resetAll()
        tableView.reloadData()
        statusLabel.stringValue = "Atajos restablecidos a los valores por defecto."
    }

    @objc private func revealJSON() {
        let url = ShortcutStore.defaultURL()
        if !FileManager.default.fileExists(atPath: url.path) {
            ShortcutStore.shared.resetAll()
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func closeAction() {
        close()
    }

    // MARK: - Tabla

    func numberOfRows(in tableView: NSTableView) -> Int {
        ShortcutStore.shared.all().count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let commands = ShortcutStore.shared.all()
        guard row < commands.count else { return nil }
        let binding = commands[row]
        let columnId = tableColumn?.identifier.rawValue ?? "command"
        let text = columnId == "command"
            ? (ShortcutStore.displayNames[binding.command] ?? binding.command)
            : binding.displayString

        let identifier = NSUserInterfaceItemIdentifier("ShortcutCell-\(columnId)")
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
        label.font = .systemFont(ofSize: 12)
        label.textColor = columnId == "command" ? .labelColor : .secondaryLabelColor
        return cell
    }
}
