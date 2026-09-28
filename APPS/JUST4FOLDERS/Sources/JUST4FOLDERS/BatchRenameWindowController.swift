import AppKit
import Foundation
import J4FOps

/// v1.2 — Ventana de renombrado en lote con previsualización en vivo
/// (búsqueda/reemplazo simple o regex, extensión opcional, aviso de conflictos).
final class BatchRenameWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private let urls: [URL]
    private let onFinished: (Int) -> Void

    private let findField = NSTextField()
    private let replaceField = NSTextField()
    private let regexCheck = NSButton(checkboxWithTitle: "Expresión regular", target: nil, action: nil)
    private let extensionCheck = NSButton(checkboxWithTitle: "Incluir extensión", target: nil, action: nil)
    private let tableView = NSTableView()
    private let infoLabel = NSTextField(labelWithString: "")
    private let renameButton = NSButton(title: "Renombrar", target: nil, action: nil)

    private var plan: [BatchRenamer.ItemPlan] = []

    init(urls: [URL], onFinished: @escaping (Int) -> Void) {
        self.urls = urls
        self.onFinished = onFinished
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 480),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Renombrar en lote — \(urls.count) elemento(s)"
        panel.isReleasedWhenClosed = false
        super.init(window: panel)
        buildUI()
        window?.initialFirstResponder = findField
        recompute()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) no soportado")
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        findField.placeholderString = "Buscar (texto o patrón)"
        replaceField.placeholderString = "Reemplazar por"
        findField.delegate = self
        replaceField.delegate = self
        for field in [findField, replaceField] {
            field.translatesAutoresizingMaskIntoConstraints = false
            field.font = .systemFont(ofSize: 12)
        }

        regexCheck.target = self
        regexCheck.action = #selector(recomputeAction)
        extensionCheck.target = self
        extensionCheck.action = #selector(recomputeAction)
        regexCheck.font = .systemFont(ofSize: 11)
        extensionCheck.font = .systemFont(ofSize: 11)
        regexCheck.state = .off
        extensionCheck.state = .off

        let findLabel = NSTextField(labelWithString: "Buscar:")
        let replaceLabel = NSTextField(labelWithString: "Reemplazar:")
        findLabel.font = .systemFont(ofSize: 12)
        replaceLabel.font = .systemFont(ofSize: 12)

        let fieldsRow = NSStackView(views: [findLabel, findField, replaceLabel, replaceField])
        fieldsRow.orientation = .horizontal
        fieldsRow.spacing = 8
        fieldsRow.translatesAutoresizingMaskIntoConstraints = false
        findField.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        replaceField.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true

        let checksRow = NSStackView(views: [regexCheck, extensionCheck])
        checksRow.orientation = .horizontal
        checksRow.spacing = 16
        checksRow.translatesAutoresizingMaskIntoConstraints = false

        // Tabla de previsualización: Actual | Nuevo
        let columnActual = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("actual"))
        columnActual.title = "Nombre actual"
        columnActual.width = 300
        let columnNew = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("nuevo"))
        columnNew.title = "Nuevo nombre / problema"
        columnNew.width = 320
        tableView.addTableColumn(columnActual)
        tableView.addTableColumn(columnNew)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.allowsMultipleSelection = false
        tableView.usesAlternatingRowBackgroundColors = true

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        infoLabel.font = .systemFont(ofSize: 11)
        infoLabel.textColor = .secondaryLabelColor
        infoLabel.translatesAutoresizingMaskIntoConstraints = false

        let cancelButton = NSButton(title: "Cancelar", target: self, action: #selector(cancelAction))
        cancelButton.keyEquivalent = "\u{1b}"
        renameButton.target = self
        renameButton.action = #selector(performRename)
        renameButton.keyEquivalent = "\r"
        renameButton.bezelStyle = .rounded

        let buttonsRow = NSStackView(views: [infoLabel, NSView(), cancelButton, renameButton])
        buttonsRow.orientation = .horizontal
        buttonsRow.spacing = 8
        buttonsRow.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(fieldsRow)
        content.addSubview(checksRow)
        content.addSubview(scrollView)
        content.addSubview(buttonsRow)

        NSLayoutConstraint.activate([
            fieldsRow.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            fieldsRow.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            fieldsRow.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),

            checksRow.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            checksRow.topAnchor.constraint(equalTo: fieldsRow.bottomAnchor, constant: 8),

            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            scrollView.topAnchor.constraint(equalTo: checksRow.bottomAnchor, constant: 8),
            scrollView.bottomAnchor.constraint(equalTo: buttonsRow.topAnchor, constant: -10),

            buttonsRow.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            buttonsRow.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            buttonsRow.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12)
        ])
    }

    @objc private func recomputeAction() {
        recompute()
    }

    func controlTextDidChange(_ obj: Notification) {
        recompute()
    }

    private func recompute() {
        let options = BatchRenamer.Options(
            find: findField.stringValue,
            replace: replaceField.stringValue,
            useRegex: regexCheck.state == .on,
            includeExtension: extensionCheck.state == .on
        )
        plan = BatchRenamer.plan(urls: urls, options: options)
        tableView.reloadData()
        updateSummary()
    }

    private func updateSummary() {
        let changes = plan.filter { $0.newName != nil }.count
        let unchanged = plan.filter { $0.status == .unchanged }.count
        let errors = plan.filter { $0.errorMessage != nil }.count
        var summary = "\(changes) cambio(s) · \(unchanged) sin cambio"
        if errors > 0 {
            summary += " · \(errors) con error"
        }
        infoLabel.stringValue = summary
        renameButton.isEnabled = changes > 0 && errors == 0
        renameButton.toolTip = errors > 0
            ? "Corrige los conflictos para poder renombrar (pasá el cursor por las filas en rojo)."
            : nil
    }

    @objc private func cancelAction() {
        close()
    }

    @objc private func performRename() {
        let result = BatchRenamer.apply(plan)
        onFinished(result.renamed)
        if !result.failures.isEmpty {
            let alert = NSAlert()
            alert.messageText = "\(result.renamed) renombrado(s), \(result.failures.count) fallo(s)."
            alert.informativeText = result.failures.prefix(8).joined(separator: "\n")
            alert.alertStyle = .warning
            alert.runModal()
        }
        close()
    }

    // MARK: - Tabla

    func numberOfRows(in tableView: NSTableView) -> Int {
        plan.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < plan.count else { return nil }
        let item = plan[row]
        let columnId = tableColumn?.identifier.rawValue ?? "actual"

        let text: String
        var color: NSColor = .labelColor
        if columnId == "actual" {
            text = item.url.lastPathComponent
        } else {
            switch item.status {
            case .rename(let name):
                text = name
            case .unchanged:
                text = "(sin cambio)"
                color = .secondaryLabelColor
            case .invalid(let message):
                text = message
                color = .systemRed
            }
        }

        let identifier = NSUserInterfaceItemIdentifier("RenameCell-\(columnId)")
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
        return cell
    }
}
