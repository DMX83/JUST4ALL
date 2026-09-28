import AppKit
import SwiftUI
import J4IAI
import J4ICore
import J4IDocs
import J4IFiling
import J4IIndex

/// Explorador de la carpeta de organización: navega por la taxonomía que construye la app.
///
/// - Panel izquierdo: **árbol de carpetas** (expandir/contraer, navegación de un clic).
/// - Lista los hijos directos desde el índice (instantáneo; nunca recorre el disco en caliente).
/// - Selección múltiple (clic, ⌘-clic, mayús-clic) con acciones en lote: «Mover a…» (journal) y papelera.
/// - Orden (nombre/tamaño/fecha) y filtro por nombre dentro de cada carpeta; duplicados visibles.
/// - Vista previa rápida con la barra espaciadora (QuickLook) sobre los ficheros seleccionados.
/// - Se actualiza solo cada 2 segundos para reflejar archivados recientes.
struct ExplorerView: View {
    @StateObject private var model = ExplorerViewModel()
    @State private var moveRequest: MoveRequest?
    @AppStorage("j4i.listDensity") private var listDensity: J4I.ListDensity = .comfortable
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Petición de «Mover a…» con buscador de destino (F13.0).
    private struct MoveRequest: Identifiable {
        let id = UUID()
        let summary: String
        let apply: (String) -> Void
    }

    var body: some View {
        Group {
            if model.rootPath == nil {
                J4IEmptyState(
                    systemImage: "folder.badge.questionmark",
                    title: "Organización sin configurar",
                    message: "Configura la carpeta de organización desde la ventana principal (menú Carpetas → Carpeta de organización…).",
                    tint: J4I.warning
                )
            } else {
                content
            }
        }
        .frame(minWidth: 760, minHeight: 480)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: model.currentPath)
        .background(WindowAccessor { window in
            model.attachWindow(window)
        })
        .onDisappear {
            model.uninstallSpaceMonitor()
        }
        .task { await model.loadInitial() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                await model.refresh()
            }
        }
        .sheet(isPresented: Binding(
            get: { model.aiSuggestionSheet != nil },
            set: { if !$0 { model.aiSuggestionSheet = nil } }
        )) {
            aiSuggestionSheetContent
        }
        .sheet(item: $moveRequest) { request in
            DestinationChooser(
                title: "Mover \(request.summary) a…",
                destinations: model.destinationChoices,
                onSelect: { destination in
                    request.apply(destination)
                    moveRequest = nil
                },
                onCancel: { moveRequest = nil },
                onCreate: { name in
                    // El executor crea la carpeta del destino al mover (F14.0).
                    request.apply(name)
                    moveRequest = nil
                }
            )
        }
    }

    /// Hoja de confirmación de las sugerencias de la IA (N3).
    private var aiSuggestionSheetContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Sugerencias de la IA", systemImage: "sparkles")
                .font(.headline)
            Text("Se moverán a su destino propuesto los elementos con sugerencia; los que apunten a «sin clasificar» se omiten (puedes revisarlos con ⌘R).")
                .font(.caption)
                .foregroundStyle(.secondary)
            List(model.aiSuggestionSheet ?? []) { row in
                HStack(spacing: 8) {
                    Image(systemName: row.isQuarantine ? "questionmark.circle" : "arrow.right.doc.on.clipboard")
                        .foregroundStyle(row.isQuarantine ? Color.orange : Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("\(row.isQuarantine ? "sin destino claro" : row.categoryPath) · \(row.sourceLabel) · confianza \(String(format: "%.2f", row.confidence))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(minHeight: 200)
            HStack {
                Spacer()
                Button("Cancelar") {
                    model.aiSuggestionSheet = nil
                }
                .keyboardShortcut(.cancelAction)
                Button("Aplicar sugerencias") {
                    model.applyAISuggestions()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 480, height: 380)
    }

    private var content: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            breadcrumb
            Divider()
            HStack(spacing: 0) {
                folderPane
                Divider()
                filePane
                Divider()
                propertiesPane
            }
            Divider()
            statusBar
        }
    }

    // MARK: - Cabecera

    private var toolbar: some View {
        HStack(spacing: J4I.Space.s) {
            Button {
                model.goUp()
            } label: {
                Label("Subir", systemImage: "arrow.up")
            }
            .disabled(!model.canGoUp)

            Button {
                model.refreshNow()
            } label: {
                Label("Actualizar", systemImage: "arrow.clockwise")
            }

            if !model.selectedFileIDs.isEmpty {
                ToolbarSeparator()
                Button {
                    let count = model.selectedFiles.count
                    moveRequest = MoveRequest(summary: "\(count) fichero(s)") { model.moveSelectedFiles(to: $0) }
                } label: {
                    Label("Mover a…", systemImage: "arrow.right.doc.on.clipboard")
                }
                .buttonStyle(.borderedProminent)
                .fixedSize()
                Button {
                    model.suggestWithAI()
                } label: {
                    Label("Sugerir con IA", systemImage: "sparkles")
                }
                .disabled(model.suggestingAI)
                .help("La IA propone destino para los seleccionados (revisas y aplicas en la hoja)")
                Button(role: .destructive) {
                    model.trashSelectedFiles()
                } label: {
                    Label(model.selectedFileIDs.count > 1 ? "Papelera (\(model.selectedFileIDs.count))" : "Papelera", systemImage: "trash")
                }
                .buttonStyle(.borderless)
            }

            Spacer()
        }
        .controlSize(.small)
        .padding(.horizontal, J4I.Space.m)
        .padding(.vertical, 8)
    }

    private var breadcrumb: some View {
        HStack(spacing: 4) {
            ForEach(Array(model.breadcrumb.enumerated()), id: \.offset) { index, crumb in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Button(crumb.title) {
                    model.navigate(to: crumb.path)
                }
                .buttonStyle(.plain)
                .font(.caption.weight(index == model.breadcrumb.count - 1 ? .semibold : .regular))
                .foregroundStyle(index == model.breadcrumb.count - 1 ? .primary : .secondary)
            }
            Spacer()
            if let error = model.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Paneles

    private var folderPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Carpetas", systemImage: "folder.fill") {
                HStack(spacing: 2) {
                    GhostIconButton(systemImage: "chevron.down.circle", help: "Expandir todo") {
                        model.expandAll()
                    }
                    GhostIconButton(systemImage: "chevron.right.circle", help: "Contraer todo") {
                        model.collapseAll()
                    }
                }
            }
            if model.tree.isEmpty {
                Spacer()
                Text("Sin subcarpetas")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                List {
                    ForEach(model.visibleTreeRows) { row in
                        treeRow(row)
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .frame(minWidth: 220, idealWidth: 240, maxWidth: 320)
    }

    /// Fila del árbol: chevron (expandir/contraer) + icono + nombre + nº de ficheros; un clic navega.
    private func treeRow(_ row: ExplorerViewModel.TreeRow) -> some View {
        let node = row.node
        let isCurrent = node.entry.path == model.currentPath
        let isExpanded = model.expandedFolderIDs.contains(node.id)
        return HStack(spacing: 4) {
            Group {
                if node.children.isEmpty {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 3))
                        .foregroundStyle(.quaternary)
                } else {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 12)
            .contentShape(Rectangle())
            .onTapGesture { model.toggleExpanded(node) }

            Image(systemName: isCurrent ? "folder.fill" : "folder")
                .foregroundStyle(isCurrent ? J4I.brand : Color.secondary)
            Text(node.entry.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .fontWeight(isCurrent ? .semibold : .regular)
            Spacer(minLength: 4)
            if let count = model.folderStats[node.id]?.fileCount {
                Text("\(count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, CGFloat(row.depth) * 12)
        .padding(.vertical, listDensity.scaled(3))
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: J4I.Radius.small, style: .continuous)
                .fill(isCurrent ? J4I.brandSoft : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: J4I.Radius.small, style: .continuous)
                .strokeBorder(isCurrent ? J4I.brand.opacity(0.35) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { model.navigateToNode(node) }
        .hoverHighlight(cornerRadius: J4I.Radius.small, intensity: 0.05)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(node.entry.name), carpeta")
        .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
        .accessibilityAction { model.navigateToNode(node) }
        .contextMenu {
            Button("Abrir") { model.navigateToNode(node) }
            Button("Mostrar en Finder") { model.reveal(node.entry) }
            Button("Copiar ruta") { model.copyPath(node.entry) }
        }
    }

    private var filePane: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: filesHeaderLabel, systemImage: "doc.text") {
                Picker("", selection: $model.fileSortKey) {
                    ForEach(ExplorerViewModel.FileSortKey.allCases) { key in
                        Text(key.label).tag(key)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 104)
                .help("Orden de los ficheros de esta carpeta")
            }
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("Filtrar por nombre…", text: $model.filterText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: J4I.Radius.small, style: .continuous)
                    .fill(J4I.well)
            )
            .overlay(
                RoundedRectangle(cornerRadius: J4I.Radius.small, style: .continuous)
                    .strokeBorder(J4I.hairline.opacity(0.6))
            )
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
            if model.files.isEmpty {
                Spacer()
                Text(model.emptyFilesMessage)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                List {
                    ForEach(model.files) { file in
                        HStack(spacing: 8) {
                            Image(systemName: iconName(for: file))
                                .foregroundStyle(model.selectedFileIDs.contains(file.id) ? J4I.brand : Color.secondary)
                            Text(file.name)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .fontWeight(model.selectedFileIDs.contains(file.id) ? .semibold : .regular)
                            Spacer()
                            if let modified = file.modifiedAt {
                                Text(modified, format: .dateTime.day().month().year())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(ByteCountFormatter.string(fromByteCount: file.sizeBytes, countStyle: .file))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 80, alignment: .trailing)
                        }
                        .padding(.vertical, listDensity.scaled(2))
                        .padding(.horizontal, 6)
                        .background(
                            RoundedRectangle(cornerRadius: J4I.Radius.small, style: .continuous)
                                .fill(model.selectedFileIDs.contains(file.id) ? J4I.brandSoft : Color.clear)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { model.open(file) }
                        .onTapGesture { model.handleFileClick(file) }
                        .hoverHighlight(cornerRadius: J4I.Radius.small, intensity: 0.05)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(accessibilityLabel(for: file))
                        .accessibilityAddTraits(model.selectedFileIDs.contains(file.id) ? [.isSelected] : [])
                        .accessibilityAction { model.open(file) }
                        .contextMenu {
                            Button("Abrir") { model.open(file) }
                            Button("Mostrar en Finder") { model.reveal(file) }
                            Divider()
                            Button("Copiar ruta") { model.copyPath(file) }
                            Divider()
                            Button("Mover a…") {
                                moveRequest = MoveRequest(summary: "«\(file.name)»") { model.moveSelectionOr(file, to: $0) }
                            }
                            Button("Sugerir destino (IA)", systemImage: "sparkles") { model.suggestSelectionOr(file) }
                            Button("Mover a la papelera", role: .destructive) { model.trashSelectionOr(file) }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private func accessibilityLabel(for file: IndexEntry) -> String {
        var parts = [file.name]
        if file.sizeBytes > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: file.sizeBytes, countStyle: .file))
        }
        if let modified = file.modifiedAt {
            parts.append(modified.formatted(date: .abbreviated, time: .omitted))
        }
        return parts.joined(separator: ", ")
    }

    private var filesHeaderLabel: String {
        let totalFiles = model.children.filter { !$0.isDirectory }.count
        if model.files.count != totalFiles {
            return "Ficheros (\(model.files.count) de \(totalFiles))"
        }
        return "Ficheros (\(model.files.count))"
    }

    // MARK: - Propiedades

    private var propertiesPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("Propiedades", systemImage: "info.circle")
            J4ICard(padding: 10) {
                if model.selectedFiles.count > 1 {
                    selectionProperties
                } else if let file = model.selectedFile {
                    fileProperties(file)
                } else {
                    folderProperties(title: model.currentFolderName ?? "Esta carpeta", stats: model.currentStats)
                }
            }
            .padding(.horizontal, 10)
            Spacer(minLength: 0)
        }
        .frame(minWidth: 200, idealWidth: 220, maxWidth: 260, alignment: .topLeading)
    }

    @ViewBuilder
    private func folderProperties(title: String, stats: DirectoryStats?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(J4I.brand)
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Text("Carpeta actual")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
            Divider()
                .padding(.vertical, 1)
            propertyRow("Ficheros", "\(stats?.fileCount ?? 0)")
            propertyRow("Subcarpetas", "\(stats?.directoryCount ?? 0)")
            propertyRow("Tamaño total", ByteCountFormatter.string(fromByteCount: stats?.totalSizeBytes ?? 0, countStyle: .file))
        }
    }

    @ViewBuilder
    private func fileProperties(_ file: IndexEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: iconName(for: file))
                    .font(.system(size: 12))
                    .foregroundStyle(J4I.brand)
                Text(file.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(3)
            }
            Divider()
                .padding(.vertical, 1)
            propertyRow("Tipo", file.ext.isEmpty ? "—" : ".\(file.ext)")
            propertyRow("Tamaño", ByteCountFormatter.string(fromByteCount: file.sizeBytes, countStyle: .file))
            if let modified = file.modifiedAt {
                propertyRow("Modificado", modified.formatted(date: .abbreviated, time: .shortened))
            }
            propertyRow("Ruta", (file.path as NSString).abbreviatingWithTildeInPath)
            if let duplicateOfPath = model.duplicateOfPath {
                propertyRow("Duplicado de", (duplicateOfPath as NSString).abbreviatingWithTildeInPath)
                Button("Revelar duplicado") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: duplicateOfPath)])
                }
                .controlSize(.small)
            }
            HStack(spacing: 6) {
                Button("Abrir") { model.open(file) }
                Button("Revelar") { model.reveal(file) }
            }
            .controlSize(.small)
            Button("Mover a la papelera", role: .destructive) { model.trash(file) }
                .controlSize(.small)
        }
    }

    @ViewBuilder
    private var selectionProperties: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("\(model.selectedFiles.count) ficheros", systemImage: "square.stack.3d.up")
                .font(.system(size: 12.5, weight: .semibold))
            propertyRow("Tamaño total", ByteCountFormatter.string(fromByteCount: model.selectedFiles.reduce(0) { $0 + $1.sizeBytes }, countStyle: .file))
            Button {
                let count = model.selectedFiles.count
                moveRequest = MoveRequest(summary: "\(count) fichero(s)") { model.moveSelectedFiles(to: $0) }
            } label: {
                Label("Mover a…", systemImage: "arrow.right.doc.on.clipboard")
            }
            .controlSize(.small)
            .fixedSize()
            Button("Mover a la papelera", role: .destructive) {
                model.trashSelectedFiles()
            }
            .controlSize(.small)
        }
    }

    private func propertyRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 12))
                .lineLimit(3)
                .textSelection(.enabled)
        }
    }

    private var statusBar: some View {
        HStack(spacing: J4I.Space.s) {
            Text("\(model.folders.count) carpeta(s) · \(model.files.count) fichero(s)")
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
            if let action = model.actionMessage {
                Text("·")
                    .font(.system(size: 11))
                    .foregroundStyle(.quaternary)
                Text(action)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(model.rootDisplay)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, J4I.Space.m)
        .padding(.vertical, 7)
    }

    private func iconName(for entry: IndexEntry) -> String {
        switch entry.ext {
        case "pdf": return "doc.richtext"
        case "jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "tiff", "bmp", "svg": return "photo"
        case "mp4", "mov", "mkv", "avi", "webm", "m4v": return "film"
        case "mp3", "m4a", "wav", "aiff", "flac", "ogg": return "music.note"
        case "zip", "rar", "7z", "tar", "gz": return "archivebox"
        case "exe", "msi", "dmg", "pkg": return "shippingbox"
        default: return "doc"
        }
    }
}

/// Estado del explorador: navegación + listado de hijos directos desde el índice.
@MainActor
final class ExplorerViewModel: ObservableObject {
    struct Breadcrumb {
        let title: String
        let path: String
    }

    /// Nodo del árbol de carpetas del panel izquierdo.
    struct FolderNode: Identifiable {
        let entry: IndexEntry
        var children: [FolderNode]

        var id: Int64 { entry.id }
    }

    /// Fila visible del árbol (nodo + profundidad para la indentación).
    struct TreeRow: Identifiable {
        let node: FolderNode
        let depth: Int

        var id: Int64 { node.id }
    }

    @Published private(set) var currentPath: String?
    @Published private(set) var children: [IndexEntry] = []
    @Published private(set) var folderStats: [Int64: DirectoryStats] = [:]
    @Published private(set) var currentStats: DirectoryStats?
    /// Árbol completo de carpetas de la organización (panel izquierdo) y nodos expandidos.
    @Published private(set) var tree: [FolderNode] = []
    @Published var expandedFolderIDs: Set<Int64> = []
    enum FileSortKey: String, CaseIterable, Identifiable {
        case name
        case size
        case date

        var id: String { rawValue }

        var label: String {
            switch self {
            case .name: return "Nombre"
            case .size: return "Tamaño"
            case .date: return "Fecha"
            }
        }
    }

    /// Fila de la hoja «Sugerencias de la IA» (N3).
    struct AISuggestionRow: Identifiable, Equatable {
        let id: String
        let name: String
        let categoryPath: String
        let confidence: Double
        let sourceLabel: String
        let isQuarantine: Bool
    }

    @Published var selectedFileIDs: Set<Int64> = []
    /// Hoja de sugerencias de la IA (nil = cerrada).
    @Published var aiSuggestionSheet: [AISuggestionRow]?
    @Published private(set) var suggestingAI = false
    @Published var errorMessage: String?
    @Published var actionMessage: String?
    @Published var duplicateOfPath: String?
    @Published var fileSortKey: FileSortKey = .name
    @Published var filterText: String = ""

    private let index = SearchIndex.shared
    private let spaceMonitor = QuickLookSpaceMonitor()
    private var selectionAnchorID: Int64?
    private var duplicateEvaluatedPath: String?
    private var duplicateTask: Task<Void, Never>?

    var rootPath: String? { FilingConfiguration.rootPath }

    var folders: [IndexEntry] { children.filter(\.isDirectory) }

    /// Ficheros visibles de la carpeta actual: filtrados por nombre y ordenados.
    var files: [IndexEntry] {
        Self.visibleFiles(from: children, filter: filterText, sort: fileSortKey)
    }

    /// Ordenación + filtro puros (testeables): sin carpetas; nombre asc, tamaño y fecha desc.
    nonisolated static func visibleFiles(from entries: [IndexEntry], filter: String, sort: FileSortKey) -> [IndexEntry] {
        let filesOnly = entries.filter { !$0.isDirectory }
        let trimmed = filter.trimmingCharacters(in: .whitespaces)
        let filtered = trimmed.isEmpty ? filesOnly : filesOnly.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
        switch sort {
        case .name:
            return filtered.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .size:
            return filtered.sorted { $0.sizeBytes > $1.sizeBytes }
        case .date:
            return filtered.sorted { ($0.modifiedAt ?? .distantPast) > ($1.modifiedAt ?? .distantPast) }
        }
    }

    var destinationChoices: [String] {
        guard let rootPath else {
            return DefaultTaxonomy.allRelativePaths.filter { $0 != DefaultTaxonomy.quarantineRelativePath }
        }
        // Inventario en disco (F14.0): incluye categorías creadas al momento o a mano.
        return TaxonomyInventory.availableDestinations(rootURL: URL(fileURLWithPath: rootPath, isDirectory: true))
    }

    var selectedFiles: [IndexEntry] {
        files.filter { selectedFileIDs.contains($0.id) }
    }

    var selectedFile: IndexEntry? {
        selectedFiles.count == 1 ? selectedFiles.first : nil
    }

    /// Mensaje del panel de ficheros cuando no hay ficheros visibles.
    var emptyFilesMessage: String {
        let trimmed = filterText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            return "Ningún fichero de esta carpeta coincide con «\(trimmed)»."
        }
        let totalFiles = currentStats?.fileCount ?? 0
        if totalFiles > 0 {
            return "Los ficheros están dentro de las subcarpetas (\(totalFiles) en total). Selecciona una carpeta del panel izquierdo."
        }
        return "Esta carpeta no contiene ficheros."
    }

    var canGoUp: Bool {
        guard let currentPath, let rootPath else { return false }
        return currentPath != standardized(rootPath)
    }

    var currentPathDisplay: String {
        guard let currentPath, let rootPath else { return "" }
        let root = standardized(rootPath)
        guard currentPath.hasPrefix(root) else { return (currentPath as NSString).abbreviatingWithTildeInPath }
        let relative = String(currentPath.dropFirst(root.count))
        return (root as NSString).lastPathComponent + relative
    }

    var rootDisplay: String {
        guard let rootPath else { return "" }
        return (rootPath as NSString).abbreviatingWithTildeInPath
    }

    var breadcrumb: [Breadcrumb] {
        guard let rootPath, let currentPath else { return [] }
        let root = standardized(rootPath)
        var result = [Breadcrumb(title: (root as NSString).lastPathComponent, path: root)]
        guard currentPath.hasPrefix(root + "/") else { return result }
        let relative = String(currentPath.dropFirst(root.count + 1))
        var accumulated = root
        for component in relative.split(separator: "/") {
            accumulated += "/" + component
            result.append(Breadcrumb(title: String(component), path: accumulated))
        }
        return result
    }

    func loadInitial() async {
        if currentPath == nil, let rootPath {
            currentPath = standardized(rootPath)
        }
        await refresh()
        if let currentPath {
            expandAncestors(ofPath: currentPath)
            if let node = Self.findNode(withPath: currentPath, in: tree) {
                expandedFolderIDs.insert(node.id)
            }
        }
    }

    /// Navega a la carpeta de un nodo del árbol: la marca como actual, expande y refresca.
    func navigateToNode(_ node: FolderNode) {
        expandedFolderIDs.insert(node.id)
        navigate(to: node.entry.path)
    }

    func navigate(to path: String) {
        currentPath = path
        selectedFileIDs = []
        selectionAnchorID = nil
        expandAncestors(ofPath: path)
        syncSelectionInfo()
        Task { await refresh() }
    }

    func toggleExpanded(_ node: FolderNode) {
        if expandedFolderIDs.contains(node.id) {
            expandedFolderIDs.remove(node.id)
        } else {
            expandedFolderIDs.insert(node.id)
        }
    }

    func expandAll() {
        expandedFolderIDs = Set(Self.flatten(tree).map(\.id))
    }

    func collapseAll() {
        expandedFolderIDs = []
    }

    func goUp() {
        guard let currentPath, let rootPath else { return }
        let root = standardized(rootPath)
        guard currentPath != root else { return }
        let parent = (currentPath as NSString).deletingLastPathComponent
        navigate(to: parent.hasPrefix(root) ? parent : root)
    }

    func refresh() async {
        guard let currentPath, let rootPath, standardized(currentPath).hasPrefix(standardized(rootPath)) else { return }
        do {
            let listing = try await index.children(ofDirectory: currentPath)
            children = listing
            var stats: [Int64: DirectoryStats] = [:]
            for entry in listing where entry.isDirectory {
                stats[entry.id] = try? await index.subtreeStats(forDirectory: entry.path)
            }
            folderStats.merge(stats) { _, new in new }
            currentStats = try? await index.subtreeStats(forDirectory: currentPath)
            let fileIDs = Set(listing.filter { !$0.isDirectory }.map(\.id))
            selectedFileIDs.formIntersection(fileIDs)
            errorMessage = nil
            await rebuildTreeIfNeeded()
            syncSelectionInfo()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Árbol de carpetas (panel izquierdo)

    private var lastTreeBuild: Date?

    /// Filas visibles del árbol según lo expandido (pura y testeable).
    var visibleTreeRows: [TreeRow] {
        Self.visibleRows(of: tree, expanded: expandedFolderIDs)
    }

    nonisolated static func visibleRows(of nodes: [FolderNode], expanded: Set<Int64>) -> [TreeRow] {
        var rows: [TreeRow] = []
        func walk(_ nodes: [FolderNode], depth: Int) {
            for node in nodes {
                rows.append(TreeRow(node: node, depth: depth))
                if expanded.contains(node.id) {
                    walk(node.children, depth: depth + 1)
                }
            }
        }
        walk(nodes, depth: 0)
        return rows
    }

    nonisolated static func flatten(_ nodes: [FolderNode]) -> [FolderNode] {
        nodes.flatMap { [$0] + flatten($0.children) }
    }

    nonisolated static func findNode(withPath path: String, in nodes: [FolderNode]) -> FolderNode? {
        for node in nodes {
            if node.entry.path == path { return node }
            if let found = findNode(withPath: path, in: node.children) { return found }
        }
        return nil
    }

    nonisolated static func folderTree(at path: String, index: SearchIndex, depth: Int) async -> [FolderNode] {
        guard depth < 6 else { return [] }
        let listing = (try? await index.children(ofDirectory: path)) ?? []
        var nodes: [FolderNode] = []
        for entry in listing where entry.isDirectory {
            let children = await folderTree(at: entry.path, index: index, depth: depth + 1)
            nodes.append(FolderNode(entry: entry, children: children))
        }
        return nodes.sorted { $0.entry.name.localizedStandardCompare($1.entry.name) == .orderedAscending }
    }

    /// Reconstruye el árbol (estructura + contadores) como mucho cada ~8 s; `forceTreeRebuild()` lo salta.
    private func rebuildTreeIfNeeded() async {
        if let lastTreeBuild, Date().timeIntervalSince(lastTreeBuild) < 8 { return }
        lastTreeBuild = Date()
        guard let rootPath else {
            tree = []
            return
        }
        let built = await Self.folderTree(at: standardized(rootPath), index: index, depth: 0)
        tree = built
        var stats: [Int64: DirectoryStats] = [:]
        for node in Self.flatten(built) {
            stats[node.id] = try? await index.subtreeStats(forDirectory: node.entry.path)
        }
        folderStats.merge(stats) { _, new in new }
    }

    /// Fuerza la reconstrucción en el siguiente refresco (tras mover/borrar o «Actualizar»).
    func forceTreeRebuild() {
        lastTreeBuild = nil
    }

    func refreshNow() {
        forceTreeRebuild()
        Task { await refresh() }
    }

    private func expandAncestors(ofPath path: String) {
        guard let rootPath else { return }
        let root = standardized(rootPath)
        var current = (path as NSString).deletingLastPathComponent
        while current.count >= root.count, current.hasPrefix(root) {
            if let node = Self.findNode(withPath: current, in: tree) {
                expandedFolderIDs.insert(node.id)
            }
            if current == root { break }
            current = (current as NSString).deletingLastPathComponent
        }
    }

    var currentFolderName: String? {
        currentPath.map { ($0 as NSString).lastPathComponent }
    }

    func open(_ file: IndexEntry) {
        guard FileManager.default.fileExists(atPath: file.path) else {
            errorMessage = "La ruta ya no existe: \(file.name)"
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: file.path))
    }

    func reveal(_ entry: IndexEntry) {
        guard FileManager.default.fileExists(atPath: entry.path) else {
            errorMessage = "La ruta ya no existe: \(entry.name)"
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: entry.path)])
    }

    func copyPath(_ entry: IndexEntry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(entry.path, forType: .string)
    }

    // MARK: - Selección múltiple

    /// Clic en una fila: selección simple; ⌘-clic alterna; mayús-clic selecciona el rango visible.
    func handleFileClick(_ file: IndexEntry) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if selectedFileIDs.contains(file.id) {
                selectedFileIDs.remove(file.id)
            } else {
                selectedFileIDs.insert(file.id)
            }
            selectionAnchorID = file.id
        } else if flags.contains(.shift), let anchorID = selectionAnchorID,
                  let anchorIndex = files.firstIndex(where: { $0.id == anchorID }) {
            let targetIndex = files.firstIndex(where: { $0.id == file.id }) ?? anchorIndex
            let range = anchorIndex <= targetIndex ? anchorIndex...targetIndex : targetIndex...anchorIndex
            selectedFileIDs = Set(files[range].map(\.id))
        } else {
            selectedFileIDs = [file.id]
            selectionAnchorID = file.id
        }
        syncSelectionInfo()
    }

    /// Mueve los seleccionados a la Papelera (manual y reversible; el motor automático nunca borra).
    func trashSelectedFiles() {
        performTrash(selectedFiles)
    }

    /// Mueve un solo fichero a la Papelera.
    func trash(_ file: IndexEntry) {
        performTrash([file])
    }

    /// Papelera desde el menú contextual: si la fila forma parte de una multiselección, actúa en lote.
    func trashSelectionOr(_ file: IndexEntry) {
        let targets = selectedFileIDs.contains(file.id) && selectedFileIDs.count > 1 ? selectedFiles : [file]
        performTrash(targets)
    }

    /// Mueve los seleccionados a la categoría elegida (journal + undo + índice al momento).
    func moveSelectedFiles(to destination: String) {
        performMove(selectedFiles, to: destination)
    }

    /// Pide a la IA destinos para los seleccionados y abre la hoja de sugerencias (N3).
    func suggestWithAI() {
        let targets = selectedFiles
        guard let rootPath, !targets.isEmpty, !suggestingAI else { return }
        suggestingAI = true
        errorMessage = nil
        actionMessage = "Consultando a la IA…"
        Task {
            let coordinator = FilingCoordinator(
                index: index,
                rootURL: URL(fileURLWithPath: rootPath, isDirectory: true),
                advisor: DeepSeekFilingAdvisor()
            )
            var rows: [AISuggestionRow] = []
            for entry in targets {
                // Caché persistente: misma pregunta + mismo archivo + misma skill → sin gastar tokens.
                if let cached = AISuggestionStore.shared.suggestion(forPath: entry.path, sizeBytes: entry.sizeBytes, modifiedAt: entry.modifiedAt) {
                    rows.append(AISuggestionRow(
                        id: entry.path,
                        name: entry.name,
                        categoryPath: cached.categoryPath,
                        confidence: cached.confidence,
                        sourceLabel: "\(cached.source.rawValue) · caché",
                        isQuarantine: cached.isQuarantine
                    ))
                    continue
                }
                if let suggestion = await coordinator.proposeDestination(for: URL(fileURLWithPath: entry.path)) {
                    if suggestion.source == .ai {
                        AISuggestionStore.shared.store(suggestion, forPath: entry.path, sizeBytes: entry.sizeBytes, modifiedAt: entry.modifiedAt)
                    }
                    rows.append(AISuggestionRow(
                        id: entry.path,
                        name: entry.name,
                        categoryPath: suggestion.categoryPath,
                        confidence: suggestion.confidence,
                        sourceLabel: suggestion.source.rawValue,
                        isQuarantine: suggestion.isQuarantine
                    ))
                }
            }
            aiSuggestionSheet = rows.isEmpty ? nil : rows
            if rows.isEmpty {
                errorMessage = "No se pudo obtener ninguna sugerencia."
            }
            suggestingAI = false
            actionMessage = nil
        }
    }

    /// Desde el menú contextual: garantiza que la fila esté en la selección y consulta a la IA.
    func suggestSelectionOr(_ file: IndexEntry) {
        if !selectedFileIDs.contains(file.id) {
            selectedFileIDs = [file.id]
            selectionAnchorID = file.id
            syncSelectionInfo()
        }
        suggestWithAI()
    }

    /// Aplica las sugerencias de la hoja: mueve cada fichero a su categoría propuesta
    /// (journal/undo/colisiones vía `reclassify`); los que apuntan a sin clasificar se omiten.
    func applyAISuggestions() {
        guard let rootPath, let rows = aiSuggestionSheet else { return }
        aiSuggestionSheet = nil
        let applicable = rows.filter { !$0.isQuarantine }
        guard !applicable.isEmpty else {
            actionMessage = "La IA no propone destino para la selección (todo apunta a «sin clasificar»)."
            return
        }
        Task {
            let coordinator = FilingCoordinator(
                index: index,
                rootURL: URL(fileURLWithPath: rootPath, isDirectory: true)
            )
            var moved = 0
            var failures: [String] = []
            for row in applicable {
                let outcome = await coordinator.reclassify(fileAt: URL(fileURLWithPath: row.id), to: row.categoryPath)
                if outcome.action == "move" {
                    moved += 1
                    AISuggestionStore.shared.remove(forPath: row.id)
                } else {
                    failures.append("«\(row.name)»")
                }
            }
            var message = "IA: movidos \(moved) de \(applicable.count)"
            let omitted = rows.count - applicable.count
            if omitted > 0 {
                message += " · \(omitted) sin destino (omitidos)"
            }
            if !failures.isEmpty {
                message += " · errores: \(failures.prefix(3).joined(separator: ", "))"
            }
            actionMessage = message
            selectedFileIDs = []
            forceTreeRebuild()
            await refresh()
        }
    }

    /// Movimiento desde el menú contextual: en lote si la fila está en una multiselección.
    func moveSelectionOr(_ file: IndexEntry, to destination: String) {
        let targets = selectedFileIDs.contains(file.id) && selectedFileIDs.count > 1 ? selectedFiles : [file]
        performMove(targets, to: destination)
    }

    private func performTrash(_ targets: [IndexEntry]) {
        guard !targets.isEmpty else { return }
        errorMessage = nil
        actionMessage = nil
        let fileManager = FileManager.default
        var trashed: [IndexEntry] = []
        var failures: [String] = []
        for entry in targets {
            guard fileManager.fileExists(atPath: entry.path) else {
                failures.append("«\(entry.name)» (ya no existe)")
                continue
            }
            do {
                try fileManager.trashItem(at: URL(fileURLWithPath: entry.path), resultingItemURL: nil)
                trashed.append(entry)
                J4Log.info(.app, "Papelera: «\(entry.name)» movido a la papelera desde el explorador.")
            } catch {
                failures.append("«\(entry.name)»")
            }
        }
        guard !trashed.isEmpty else {
            errorMessage = "No se pudo mover a la papelera: \(failures.prefix(3).joined(separator: ", "))"
            return
        }
        selectedFileIDs.subtract(trashed.map(\.id))
        let paths = trashed.map(\.path)
        Task {
            for path in paths {
                if let root = try? await index.rootID(containing: path) {
                    _ = try? await index.removeEntries(rootID: root.id, paths: [path])
                }
            }
            if trashed.count == 1, let only = trashed.first {
                actionMessage = "«\(only.name)» → Papelera"
            } else {
                var message = "\(trashed.count) fichero(s) → Papelera"
                if !failures.isEmpty {
                    message += " · errores: \(failures.prefix(3).joined(separator: ", "))"
                }
                actionMessage = message
            }
            forceTreeRebuild()
            await refresh()
        }
    }

    private func performMove(_ targets: [IndexEntry], to destination: String) {
        guard let rootPath, !targets.isEmpty else { return }
        errorMessage = nil
        actionMessage = nil
        Task {
            let coordinator = FilingCoordinator(
                index: index,
                rootURL: URL(fileURLWithPath: rootPath, isDirectory: true)
            )
            var movedCount = 0
            var firstDetail: String?
            var failures: [String] = []
            for entry in targets {
                let outcome = await coordinator.reclassify(fileAt: URL(fileURLWithPath: entry.path), to: destination)
                if outcome.action == "move" {
                    movedCount += 1
                    if firstDetail == nil {
                        let finalName = (outcome.destinationPath as NSString).lastPathComponent
                        var detail = "«\(entry.name)» → \(outcome.categoryPath)"
                        if finalName != entry.name {
                            detail += " (guardado como «\(finalName)» para no sobrescribir)"
                        }
                        firstDetail = detail
                    }
                } else {
                    failures.append("«\(entry.name)»")
                }
            }
            if targets.count == 1 {
                actionMessage = firstDetail
            } else {
                var message = "Movidos \(movedCount) de \(targets.count) → \(destination)"
                if !failures.isEmpty {
                    message += " · errores: \(failures.prefix(3).joined(separator: ", "))"
                }
                actionMessage = message
            }
            if movedCount == 0 {
                errorMessage = "No se pudo mover: \(failures.prefix(3).joined(separator: ", "))"
            }
            selectedFileIDs.subtract(targets.map(\.id))
            forceTreeRebuild()
            await refresh()
        }
    }

    // MARK: - Duplicados

    /// Comprueba (por hash, en segundo plano) si el fichero seleccionado ya está archivado en otro sitio.
    private func syncDuplicateInfo() {
        let currentPath = selectedFiles.count == 1 ? selectedFiles[0].path : nil
        guard currentPath != duplicateEvaluatedPath else { return }
        duplicateEvaluatedPath = currentPath
        duplicateTask?.cancel()
        duplicateOfPath = nil
        guard let currentPath else { return }
        duplicateTask = Task { [weak self] in
            guard let self else { return }
            let hash = await Task.detached(priority: .utility) { DocumentAnalyzer.sha256Hex(of: URL(fileURLWithPath: currentPath)) }.value
            guard !Task.isCancelled, let hash else { return }
            guard let cached = try? await self.index.loadCachedAnalysis(hash: hash),
                  let filedPath = cached.filedPath,
                  !filedPath.isEmpty,
                  self.standardized(filedPath) != self.standardized(currentPath),
                  FileManager.default.fileExists(atPath: filedPath) else { return }
            guard !Task.isCancelled else { return }
            self.duplicateOfPath = filedPath
        }
    }

    // MARK: - Vista previa rápida (QuickLook con la barra espaciadora)

    func attachWindow(_ window: NSWindow?) {
        guard let window else { return }
        spaceMonitor.window = window
        spaceMonitor.install()
    }

    func uninstallSpaceMonitor() {
        spaceMonitor.uninstall()
        spaceMonitor.urls = []
        QuickLookController.shared.close()
    }

    /// Sincroniza lo que depende de la selección: monitor de espacio, QuickLook abierto y duplicados.
    private func syncSelectionInfo() {
        spaceMonitor.urls = selectedFiles.map { URL(fileURLWithPath: $0.path) }
        refreshQuickLookIfVisible()
        syncDuplicateInfo()
    }

    private func refreshQuickLookIfVisible() {
        guard QuickLookController.shared.isVisible else { return }
        let urls = selectedFiles.map { URL(fileURLWithPath: $0.path) }
        if urls.isEmpty {
            QuickLookController.shared.close()
        } else {
            QuickLookController.shared.setURLs(urls)
        }
    }

    private func standardized(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}
