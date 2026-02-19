import AppKit
import Foundation
import J4FOps

final class TaskManagerWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let jobQueue: JobQueueService

    private let tableView = NSTableView()
    private let summaryLabel = NSTextField(labelWithString: "Sin tareas")
    private let pauseButton = NSButton(title: "Pause", target: nil, action: nil)
    private let resumeButton = NSButton(title: "Resume", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private let logView = NSTextView()

    private var eventToken: UUID?
    private var orderedIds: [UUID] = []
    private var snapshotsById: [UUID: JobSnapshot] = [:]
    private var logsById: [UUID: [String]] = [:]

    init(jobQueue: JobQueueService) {
        self.jobQueue = jobQueue
        let content = NSViewController()
        let window = NSWindow(contentViewController: content)
        window.title = "Tasks"
        window.setContentSize(NSSize(width: 860, height: 520))
        window.styleMask.insert([.titled, .closable, .miniaturizable, .resizable])
        super.init(window: window)
        shouldCascadeWindows = true
        setupUI(in: content)
        bootstrapSnapshots()
        subscribeEvents()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let eventToken {
            jobQueue.unsubscribeEvents(eventToken)
        }
    }

    func showAndFocus() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func setupUI(in content: NSViewController) {
        let root = content.view
        root.translatesAutoresizingMaskIntoConstraints = false

        let topBar = NSStackView()
        topBar.orientation = .horizontal
        topBar.spacing = 8
        topBar.translatesAutoresizingMaskIntoConstraints = false
        summaryLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        summaryLabel.setAccessibilityLabel("Resumen de tareas")

        pauseButton.target = self
        pauseButton.action = #selector(pauseSelected)
        pauseButton.bezelStyle = .rounded
        pauseButton.setAccessibilityLabel("Pausar tarea seleccionada")
        resumeButton.target = self
        resumeButton.action = #selector(resumeSelected)
        resumeButton.bezelStyle = .rounded
        resumeButton.setAccessibilityLabel("Reanudar tarea seleccionada")
        cancelButton.target = self
        cancelButton.action = #selector(cancelSelected)
        cancelButton.bezelStyle = .rounded
        cancelButton.setAccessibilityLabel("Cancelar tarea seleccionada")

        topBar.addArrangedSubview(summaryLabel)
        topBar.addArrangedSubview(NSView())
        topBar.addArrangedSubview(pauseButton)
        topBar.addArrangedSubview(resumeButton)
        topBar.addArrangedSubview(cancelButton)

        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        split.translatesAutoresizingMaskIntoConstraints = false

        let jobsScroll = NSScrollView()
        jobsScroll.hasVerticalScroller = true
        jobsScroll.translatesAutoresizingMaskIntoConstraints = false
        jobsScroll.setAccessibilityLabel("Lista de tareas")
        configureTable()
        jobsScroll.documentView = tableView

        let logScroll = NSScrollView()
        logScroll.hasVerticalScroller = true
        logScroll.translatesAutoresizingMaskIntoConstraints = false
        logScroll.setAccessibilityLabel("Log de tarea")
        logView.isEditable = false
        logView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        logView.string = "Selecciona una tarea para ver eventos."
        logView.setAccessibilityLabel("Detalle de eventos")
        logScroll.documentView = logView

        split.addArrangedSubview(jobsScroll)
        split.addArrangedSubview(logScroll)

        root.addSubview(topBar)
        root.addSubview(split)

        NSLayoutConstraint.activate([
            topBar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            topBar.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            topBar.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            split.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            split.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            split.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 8),
            split.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
            jobsScroll.widthAnchor.constraint(equalToConstant: 470)
        ])
    }

    private func configureTable() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.headerView = NSTableHeaderView()
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsEmptySelection = true
        tableView.setAccessibilityLabel("Tabla de tareas")

        let idCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("id"))
        idCol.title = "Job"
        idCol.width = 120
        tableView.addTableColumn(idCol)

        let typeCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("type"))
        typeCol.title = "Type"
        typeCol.width = 90
        tableView.addTableColumn(typeCol)

        let stateCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("state"))
        stateCol.title = "State"
        stateCol.width = 90
        tableView.addTableColumn(stateCol)

        let progressCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("progress"))
        progressCol.title = "Progress"
        progressCol.width = 170
        tableView.addTableColumn(progressCol)
    }

    private func bootstrapSnapshots() {
        for snap in jobQueue.persistedSnapshots() {
            snapshotsById[snap.id] = snap
            if !orderedIds.contains(snap.id) {
                orderedIds.append(snap.id)
            }
        }
        reloadUI()
    }

    private func subscribeEvents() {
        eventToken = jobQueue.subscribeEvents { [weak self] event in
            DispatchQueue.main.async {
                self?.consume(event: event)
            }
        }
    }

    private func consume(event: JobEvent) {
        if let snapshot = event.snapshot {
            snapshotsById[snapshot.id] = snapshot
            if !orderedIds.contains(snapshot.id) {
                orderedIds.insert(snapshot.id, at: 0)
            }
        }

        let line = formatEvent(event)
        logsById[event.jobId, default: []].append(line)
        reloadUI()

        if let selected = selectedJobId(), selected == event.jobId {
            renderLog(for: selected)
        }
    }

    private func reloadUI() {
        tableView.reloadData()
        updateSummary()
        updateButtons()
    }

    private func updateSummary() {
        let all = orderedIds.compactMap { snapshotsById[$0] }
        let running = all.filter { $0.state == .running || $0.state == .paused }.count
        summaryLabel.stringValue = "Total: \(all.count) | Activas: \(running)"
    }

    private func updateButtons() {
        guard let snap = selectedSnapshot() else {
            pauseButton.isEnabled = false
            resumeButton.isEnabled = false
            cancelButton.isEnabled = false
            return
        }
        pauseButton.isEnabled = snap.state == .running
        resumeButton.isEnabled = snap.state == .paused
        cancelButton.isEnabled = snap.state == .queued || snap.state == .running || snap.state == .paused
    }

    private func selectedJobId() -> UUID? {
        let row = tableView.selectedRow
        guard row >= 0, row < orderedIds.count else { return nil }
        return orderedIds[row]
    }

    private func selectedSnapshot() -> JobSnapshot? {
        guard let id = selectedJobId() else { return nil }
        return snapshotsById[id]
    }

    @objc private func pauseSelected() {
        guard let id = selectedJobId() else { return }
        jobQueue.pause(jobId: id)
    }

    @objc private func resumeSelected() {
        guard let id = selectedJobId() else { return }
        jobQueue.resume(jobId: id)
    }

    @objc private func cancelSelected() {
        guard let id = selectedJobId() else { return }
        jobQueue.cancel(jobId: id)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        orderedIds.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0, row < orderedIds.count else { return nil }
        guard let snapshot = snapshotsById[orderedIds[row]] else { return nil }

        let identifier = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("cell")
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

        switch identifier.rawValue {
        case "id":
            label.stringValue = String(snapshot.id.uuidString.prefix(8))
        case "type":
            label.stringValue = snapshot.type.rawValue
        case "state":
            label.stringValue = snapshot.state.rawValue
        case "progress":
            let pct = Int(snapshot.progress * 100)
            label.stringValue = "\(snapshot.processedItems)/\(snapshot.totalItems) (\(pct)%)"
        default:
            label.stringValue = ""
        }
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let id = selectedJobId() else {
            logView.string = "Selecciona una tarea para ver eventos."
            updateButtons()
            return
        }
        renderLog(for: id)
        updateButtons()
    }

    private func renderLog(for id: UUID) {
        let lines = logsById[id] ?? []
        logView.string = lines.isEmpty ? "Sin eventos." : lines.joined(separator: "\n")
        logView.scrollToEndOfDocument(nil)
    }

    private func formatEvent(_ event: JobEvent) -> String {
        let formatter = ISO8601DateFormatter()
        let ts = formatter.string(from: event.timestamp)
        let msg = event.message ?? ""
        return "\(ts) | \(event.kind.rawValue) \(msg)"
    }
}
