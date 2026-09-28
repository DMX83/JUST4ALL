import AppKit
import Foundation
import J4FOps

/// v2.0 — Ventana «Ordenar esta carpeta»: clasifica con las reglas compartidas de JUST4DESK
/// (nombre → extensión), previsualiza el destino y **mueve** (nunca copia ni borra).
/// El diario de movimientos permite «Deshacer última ordenación».
final class OrderingWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let folder: URL
    private let onFinished: (Int) -> Void

    private let destinationLabel = NSTextField(labelWithString: "")
    private let unknownCheck = NSButton(checkboxWithTitle: "Enviar los no clasificados a 99_SinClasificar", target: nil, action: nil)
    private let tableView = NSTableView()
    private let infoLabel = NSTextField(labelWithString: "")
    private let orderButton = NSButton(title: "Ordenar", target: nil, action: nil)

    private var destinationRoot: URL
    private var files: [URL] = []
    private var plan: [FolderOrderer.Item] = []
    /// v2.0 — asesor IA opcional: nil si no hay clave (`DEEPSEEK_API_KEY` o `.env.secrets`).
    private let advisor: (any FilingAdvising)? = DeepSeekFilingAdvice()
    private let aiCheck = NSButton(checkboxWithTitle: "Usar IA para los dudosos", target: nil, action: nil)
    private var recomputeTask: Task<Void, Never>?

    /// v2.3 (Panel Hub F2) — destino elegido (raxiz donde viven las categorías y los dudosos).
    var currentDestination: URL { destinationRoot }

    init(folder: URL, onFinished: @escaping (Int) -> Void) {
        self.folder = folder
        self.destinationRoot = folder
        self.onFinished = onFinished
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        let name = folder.lastPathComponent.isEmpty ? folder.path : folder.lastPathComponent
        panel.title = "Ordenar esta carpeta — \(name)"
        panel.isReleasedWhenClosed = false
        super.init(window: panel)
        loadFiles()
        buildUI()
        recompute()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) no soportado")
    }

    private func loadFiles() {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        files = contents.filter { url in
            (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let destinationPrefix = NSTextField(labelWithString: "Destino (se crean las categorías dentro):")
        destinationPrefix.font = .systemFont(ofSize: 11)
        destinationPrefix.textColor = .secondaryLabelColor
        destinationLabel.font = .systemFont(ofSize: 11)
        destinationLabel.lineBreakMode = .byTruncatingMiddle
        let changeButton = NSButton(title: "Cambiar…", target: self, action: #selector(chooseDestination))
        changeButton.controlSize = .small
        changeButton.font = .systemFont(ofSize: 11)
        changeButton.bezelStyle = .rounded

        let destinationRow = NSStackView(views: [destinationPrefix, destinationLabel, changeButton])
        destinationRow.orientation = .horizontal
        destinationRow.spacing = 8
        destinationRow.translatesAutoresizingMaskIntoConstraints = false
        destinationLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true

        unknownCheck.state = .on
        unknownCheck.font = .systemFont(ofSize: 11)
        unknownCheck.target = self
        unknownCheck.action = #selector(recomputeAction)
        unknownCheck.translatesAutoresizingMaskIntoConstraints = false

        // v2.0 — la IA solo se ofrece si hay clave configurada; consulta única por fichero dudoso.
        aiCheck.state = advisor == nil ? .off : .on
        aiCheck.isEnabled = advisor != nil
        aiCheck.font = .systemFont(ofSize: 11)
        aiCheck.target = self
        aiCheck.action = #selector(recomputeAction)
        aiCheck.toolTip = advisor == nil
            ? "Configura DEEPSEEK_API_KEY (o .env.secrets) para que la IA clasifique los dudosos."
            : "Consulta a DeepSeek solo los que las reglas no clasifican (se envía únicamente el nombre)."
        aiCheck.translatesAutoresizingMaskIntoConstraints = false

        let checksRow = NSStackView(views: [unknownCheck, aiCheck])
        checksRow.orientation = .horizontal
        checksRow.spacing = 16
        checksRow.translatesAutoresizingMaskIntoConstraints = false

        let columnActual = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("actual"))
        columnActual.title = "Actual"
        columnActual.width = 240
        let columnCategory = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("categoria"))
        columnCategory.title = "Categoría"
        columnCategory.width = 170
        let columnName = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("nuevo"))
        columnName.title = "Nuevo nombre / motivo"
        columnName.width = 260
        tableView.addTableColumn(columnActual)
        tableView.addTableColumn(columnCategory)
        tableView.addTableColumn(columnName)
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
        orderButton.target = self
        orderButton.action = #selector(performOrder)
        orderButton.keyEquivalent = "\r"
        orderButton.bezelStyle = .rounded

        let buttonsRow = NSStackView(views: [infoLabel, NSView(), cancelButton, orderButton])
        buttonsRow.orientation = .horizontal
        buttonsRow.spacing = 8
        buttonsRow.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(destinationRow)
        content.addSubview(checksRow)
        content.addSubview(scrollView)
        content.addSubview(buttonsRow)

        NSLayoutConstraint.activate([
            destinationRow.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            destinationRow.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            destinationRow.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),

            checksRow.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            checksRow.topAnchor.constraint(equalTo: destinationRow.bottomAnchor, constant: 6),

            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            scrollView.topAnchor.constraint(equalTo: checksRow.bottomAnchor, constant: 8),
            scrollView.bottomAnchor.constraint(equalTo: buttonsRow.topAnchor, constant: -10),

            buttonsRow.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            buttonsRow.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            buttonsRow.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12)
        ])

        updateDestinationLabel()
    }

    private func updateDestinationLabel() {
        destinationLabel.stringValue = destinationRoot.standardizedFileURL.path
        destinationLabel.toolTip = destinationRoot.path
    }

    @objc private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = destinationRoot
        panel.prompt = "Usar esta carpeta"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        destinationRoot = url
        updateDestinationLabel()
    }

    @objc private func recomputeAction() {
        recompute()
    }

    private func recompute() {
        recomputeTask?.cancel()
        let options = FolderOrderer.Options(categorizeUnknown: unknownCheck.state == .on)
        plan = FolderOrderer.plan(files: files, options: options)
        tableView.reloadData()
        updateSummary()

        // v2.0 — refuerzo con IA para los dudosos (si hay clave y está activado).
        guard let advisor, aiCheck.state == .on else { return }
        infoLabel.stringValue += " · consultando IA…"
        recomputeTask = Task { [weak self] in
            guard let self else { return }
            let refined = await FolderOrderer.planAsync(
                files: self.files,
                options: options,
                advisor: advisor,
                onProgress: { done, total in
                    Task { @MainActor [weak self] in
                        self?.infoLabel.stringValue = "IA: \(done)/\(total) dudosos consultados…"
                    }
                }
            )
            await MainActor.run {
                self.plan = refined
                self.tableView.reloadData()
                self.updateSummary()
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        recomputeTask?.cancel()
    }

    private func updateSummary() {
        let moves = plan.filter { $0.destinationRelativePath != nil }
        let quarantine = moves.filter { $0.isQuarantine }.count
        let skipped = plan.count - moves.count
        var summary = "\(moves.count) se archivarán (de \(plan.count))"
        if quarantine > 0 {
            summary += " · \(quarantine) sin clasificar"
        }
        if skipped > 0 {
            summary += " · \(skipped) se quedan"
        }
        infoLabel.stringValue = summary
        orderButton.isEnabled = !moves.isEmpty
    }

    @objc private func cancelAction() {
        close()
    }

    @objc private func performOrder() {
        orderButton.isEnabled = false
        let result = FolderOrderer.apply(plan, destinationRoot: destinationRoot)
        if !result.journal.isEmpty {
            OrderingJournalStore.save(result.journal, to: OrderingJournalStore.defaultURL())
        }
        onFinished(result.moved)
        if !result.failures.isEmpty {
            let alert = NSAlert()
            alert.messageText = "\(result.moved) archivado(s), \(result.failures.count) fallo(s)."
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
        switch columnId {
        case "actual":
            text = item.url.lastPathComponent
        case "categoria":
            if let path = item.destinationRelativePath {
                text = path
                color = item.isQuarantine ? .systemOrange : .labelColor
            } else {
                text = "—"
                color = .secondaryLabelColor
            }
        default:
            if let name = item.finalName {
                text = name
            } else {
                text = item.reason
                color = .secondaryLabelColor
            }
        }

        let identifier = NSUserInterfaceItemIdentifier("OrderCell-\(columnId)")
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
        label.font = .systemFont(ofSize: 11)
        cell.toolTip = item.reason
        return cell
    }
}
