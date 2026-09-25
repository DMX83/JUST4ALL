import AppKit
import SwiftUI
import J4IAI
import J4ICore
import J4IFiling
import J4IIndex

/// Cola de revisión de la cuarentena (F7.6): lista los ficheros de `99_SinClasificar`,
/// propone un destino (reglas locales) y los mueve a su categoría en un clic.
///
/// - Orden por extensión (con secciones), nombre, fecha o tamaño; selección múltiple para
///   mover varios a la vez (cada uno a su destino, o uno común para toda la selección) o
///   enviarlos a la Papelera (reversible desde el Finder).
/// - La propuesta de la IA se conserva como destino preseleccionado aunque la lista se recargue;
///   «Mover sugeridos (N)» aplica de una vez todas las propuestas (los «sin destino claro» se quedan).
/// - La operación es manual y explícita: no pasa por el modo simulación.
/// - Queda en el journal de operaciones (deshacer desde Actividad).
/// - El índice se actualiza al momento (la entrada antigua desaparece y la nueva es buscable,
///   incluido el texto para la búsqueda por contenido).
struct ReviewView: View {
    @StateObject private var model = ReviewViewModel()
    @State private var confirmMoveAll = false
    @State private var pendingSplitItem: ReviewViewModel.Item?
    /// Ruta de la fila cuyo buscador de destino está abierto (F13.0).
    @State private var chooserPath: String?
    /// Buscador de destino de la selección múltiple (F13.0).
    @State private var showSelectionChooser = false

    var body: some View {
        Group {
            if model.rootPath == nil {
                ContentUnavailableView {
                    Label("Organización sin configurar", systemImage: "folder.badge.questionmark")
                } description: {
                    Text("Configura la carpeta de organización desde la ventana principal (menú Carpetas → Carpeta de organización…).")
                }
            } else {
                content
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .task { model.load() }
    }

    private var content: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if !model.selection.isEmpty && !model.items.isEmpty {
                selectionBar
                Divider()
            }
            if model.items.isEmpty {
                emptyState
            } else {
                itemsList
            }
            Divider()
            statusBar
        }
        .confirmationDialog(
            pendingSplitItem.map { "¿Desglosar «\($0.name)» y clasificar sus elementos por separado?" } ?? "",
            isPresented: Binding(
                get: { pendingSplitItem != nil },
                set: { if !$0 { pendingSplitItem = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Desglosar") {
                if let item = pendingSplitItem {
                    model.splitFolder(item)
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("La carpeta se procesa elemento a elemento (cada fichero a su categoría; sin señal → cuarentena) y la cáscara vacía queda en origen. Deshacible desde Actividad.")
        }
    }

    // MARK: - Cabecera

    private var toolbar: some View {
        HStack(spacing: 10) {
            Label("Por revisar (\(model.items.count))", systemImage: "tray.full")
                .font(.headline)
            Spacer()
            Picker("Ordenar", selection: $model.sortKey) {
                ForEach(ReviewViewModel.SortKey.allCases) { key in
                    Text(key.label).tag(key)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
            .help("Orden de la lista: por extensión (con secciones), nombre, fecha o tamaño")
            Button {
                model.reevaluateWithAI()
            } label: {
                Label("Reevaluar con IA", systemImage: "sparkles")
            }
            .disabled(model.items.isEmpty || model.reevaluating)
            .help("Propone destinos con la IA (skill v\(FilingSkill.version)) para la selección — o para todo si no hay selección; lo ya consultado se reutiliza de la caché (no gasta tokens)")
            if model.reevaluating {
                ProgressView()
                    .controlSize(.small)
            }
            Button {
                confirmMoveAll = true
            } label: {
                Label("Mover sugeridos (\(model.suggestedCount))", systemImage: "arrow.right.circle")
            }
            .disabled(model.suggestedCount == 0 || model.reevaluating || !model.busyPaths.isEmpty)
            .help("Mueve de una vez todos los elementos con propuesta de la IA (los «sin destino claro» se quedan). Primero «Reevaluar con IA»")
            Button("Seleccionar todo") {
                model.selectAll()
            }
            .disabled(model.items.isEmpty || model.selection.count == model.items.count)
            Button {
                model.revealQuarantine()
            } label: {
                Label("Abrir en Finder", systemImage: "arrow.up.forward.app")
            }
            Button {
                model.load()
            } label: {
                Label("Actualizar", systemImage: "arrow.clockwise")
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .confirmationDialog(
            moveAllTitle,
            isPresented: $confirmMoveAll,
            titleVisibility: .visible
        ) {
            Button("Mover \(model.suggestedCount)") {
                model.moveAllSuggested()
            }
            Button("Cancelar", role: .cancel) {}
        }
    }

    // MARK: - Lista

    private var itemsList: some View {
        List(selection: $model.selection) {
            if model.sortKey == .ext {
                ForEach(model.extensionGroups) { group in
                    Section(header: Text(group.title)) {
                        ForEach(group.items) { item in
                            rowView(for: item)
                        }
                    }
                }
            } else {
                ForEach(model.items) { item in
                    rowView(for: item)
                }
            }
        }
        .listStyle(.inset)
    }

    private func rowView(for item: ReviewViewModel.Item) -> some View {
        HStack(spacing: 10) {
            Image(systemName: model.aiSuggestions[item.path] != nil
                  ? "sparkles"
                  : (item.isDirectory ? "folder" : "exclamationmark.triangle"))
                .foregroundStyle(model.aiSuggestions[item.path] != nil ? Color.accentColor : Color.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle(for: item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            Button {
                chooserPath = item.path
            } label: {
                HStack(spacing: 4) {
                    Text(item.destination ?? "Elegir destino…")
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                }
                .frame(width: 200, alignment: .leading)
            }
            .controlSize(.small)
            .help("Busca el destino escribiendo (p. ej. «trabajo»): aparecen la categoría y sus subcarpetas")
            .popover(isPresented: Binding(
                get: { chooserPath == item.path },
                set: { if !$0 { chooserPath = nil } }
            ), arrowEdge: .bottom) {
                DestinationChooser(
                    title: "Destino para «\(item.name)»",
                    destinations: model.destinations,
                    onSelect: { destination in
                        model.setDestination(destination, for: item.id)
                        chooserPath = nil
                    },
                    onCancel: { chooserPath = nil },
                    onCreate: { name in
                        // Se creará la carpeta al pulsar «Mover» (F14.0).
                        model.setDestination(name, for: item.id)
                        chooserPath = nil
                    }
                )
            }
            if model.busyPaths.contains(item.path) {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 60)
            } else {
                Button("Mover") {
                    model.move(item)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .frame(width: 60)
                .disabled(item.destination == nil)
            }
        }
        .padding(.vertical, 3)
        .hoverHighlight(intensity: 0.05)
        .tag(item.id)
        .contextMenu {
            Button("Mostrar en Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
            }
            if item.isDirectory {
                Button("Desglosar y organizar por ficheros…") {
                    pendingSplitItem = item
                }
            }
            if model.aiSuggestions[item.path] != nil {
                Button("Olvidar propuesta de la IA") {
                    model.forgetAISuggestion(item)
                }
            }
            Button("Mover a la papelera", role: .destructive) {
                model.trash(item)
            }
        }
    }

    /// Barra de acciones de la selección múltiple: destino común + mover en lote.
    private var selectionBar: some View {
        HStack(spacing: 10) {
            Text("\(model.selection.count) seleccionado(s)")
                .font(.callout.weight(.medium))
            Button {
                showSelectionChooser = true
            } label: {
                Label(model.selectionDestination ?? "Destino para la selección…", systemImage: "folder")
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .popover(isPresented: $showSelectionChooser, arrowEdge: .bottom) {
                DestinationChooser(
                    title: "Destino para \(model.selection.count) seleccionado(s)",
                    destinations: model.destinations,
                    onSelect: { destination in
                        model.setDestinationForSelection(destination)
                        showSelectionChooser = false
                    },
                    onCancel: { showSelectionChooser = false },
                    onCreate: { name in
                        // Se creará la carpeta al pulsar «Mover seleccionados» (F14.0).
                        model.setDestinationForSelection(name)
                        showSelectionChooser = false
                    }
                )
            }
            Button("Mover seleccionados") {
                model.moveSelected()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canMoveSelection)
            Button("Mover a la papelera", role: .destructive) {
                model.trashSelected()
            }
            .disabled(!model.canTrashSelection)
            Spacer()
            Button("Quitar selección") {
                model.selection = []
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.10))
    }

    private func subtitle(for item: ReviewViewModel.Item) -> String {
        var parts: [String] = []
        if item.isDirectory {
            parts.append("carpeta")
            if let folderSummary = item.folderSummary {
                parts.append(folderSummary)
            }
        } else {
            parts.append(ByteCountFormatter.string(fromByteCount: item.sizeBytes, countStyle: .file))
        }
        if let modified = item.modifiedAt {
            parts.append(modified.formatted(date: .abbreviated, time: .omitted))
        }
        if let ai = model.aiSuggestions[item.path] {
            if ai.folderStrategy == .split {
                parts.append("IA: cajón heterogéneo → desglosar (\(String(format: "%.2f", ai.confidence)))")
            } else if ai.isQuarantine {
                parts.append("IA: sin destino claro")
            } else {
                parts.append("IA → \(ai.categoryPath) (\(String(format: "%.2f", ai.confidence)))")
            }
        } else if let suggestion = item.suggestion {
            parts.append("sugerido: \(suggestion)")
        } else {
            parts.append("sin sugerencia automática")
        }
        return parts.joined(separator: " · ")
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Nada por revisar", systemImage: "checkmark.seal")
        } description: {
            Text("La cuarentena está vacía. Aquí aparecerán los documentos que el archivado automático no pudo clasificar, con una sugerencia de destino para reubicarlos en un clic.")
        }
    }

    /// Título del diálogo de confirmación del movimiento en lote de las propuestas de la IA.
    private var moveAllTitle: String {
        model.suggestedCount == 1
            ? "Mover 1 elemento a su destino propuesto por la IA"
            : "Mover \(model.suggestedCount) elementos a sus destinos propuestos por la IA"
    }

    // MARK: - Barra de estado

    private var statusBar: some View {
        HStack(spacing: 10) {
            if let error = model.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
            } else if let status = model.statusMessage {
                Text(status)
                    .foregroundStyle(.secondary)
            } else {
                Text("Cuarentena: \(model.quarantineDisplay)")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .font(.caption)
        .lineLimit(1)
        .truncationMode(.middle)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

/// Estado de la cola de revisión: lectura de la cuarentena + sugerencias + mover con journal.
@MainActor
final class ReviewViewModel: ObservableObject {
    struct Item: Identifiable, Equatable {
        let path: String
        let name: String
        let sizeBytes: Int64
        let modifiedAt: Date?
        let suggestion: String?
        var destination: String?
        let isDirectory: Bool
        /// Resumen del contenido cuando es carpeta («16 fichero(s) · dominante .pdf»).
        let folderSummary: String?

        init(path: String, name: String, sizeBytes: Int64, modifiedAt: Date?, suggestion: String?, destination: String?, isDirectory: Bool = false, folderSummary: String? = nil) {
            self.path = path
            self.name = name
            self.sizeBytes = sizeBytes
            self.modifiedAt = modifiedAt
            self.suggestion = suggestion
            self.destination = destination
            self.isDirectory = isDirectory
            self.folderSummary = folderSummary
        }

        var id: String { path }
    }

    enum SortKey: String, CaseIterable, Identifiable {
        case ext
        case name
        case date
        case size

        var id: String { rawValue }

        var label: String {
            switch self {
            case .ext: return "Extensión"
            case .name: return "Nombre"
            case .date: return "Fecha"
            case .size: return "Tamaño"
            }
        }
    }

    struct ExtensionGroup: Identifiable {
        let key: String
        let title: String
        let items: [Item]

        var id: String { key }
    }

    @Published var items: [Item] = []
    @Published var selection: Set<String> = []
    @Published private(set) var destinations: [String] = []
    @Published private(set) var busyPaths: Set<String> = []
    /// Orden de la lista; por defecto por extensión (con secciones).
    @Published var sortKey: SortKey = .ext {
        didSet { applySort() }
    }
    @Published var statusMessage: String?
    @Published var errorMessage: String?
    /// Sugerencias de la IA (por path) tras «Reevaluar con IA».
    @Published private(set) var aiSuggestions: [String: FilingCoordinator.Suggestion] = [:]
    @Published private(set) var reevaluating = false

    private let index = SearchIndex.shared
    private let suggestionStore = AISuggestionStore.shared

    var rootPath: String? { FilingConfiguration.rootPath }

    private var quarantineURL: URL? {
        rootPath.map {
            URL(fileURLWithPath: $0, isDirectory: true)
                .appendingPathComponent(DefaultTaxonomy.quarantineRelativePath, isDirectory: true)
        }
    }

    var quarantineDisplay: String {
        quarantineURL.map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? "—"
    }

    /// Lee la cuarentena del disco (carpeta pequeña y plana): la cola de revisión debe ser
    /// fiable aunque el índice aún no haya visto el último movimiento.
    func load() {
        errorMessage = nil
        if let rootPath {
            // Inventario en disco (F14.0): incluye categorías creadas al momento o a mano.
            destinations = TaxonomyInventory.availableDestinations(rootURL: URL(fileURLWithPath: rootPath, isDirectory: true))
        } else {
            destinations = DefaultTaxonomy.allRelativePaths.filter { $0 != DefaultTaxonomy.quarantineRelativePath }
        }
        guard let quarantineURL else {
            items = []
            selection = []
            return
        }
        let fileManager = FileManager.default
        let urls = (try? fileManager.contentsOfDirectory(
            at: quarantineURL,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        var loaded: [Item] = []
        for url in urls {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey, .isDirectoryKey])
            let isDirectory = values?.isDirectory == true
            guard values?.isRegularFile == true || isDirectory else { continue }
            let name = url.lastPathComponent
            let sizeBytes = Int64(values?.fileSize ?? 0)
            let modifiedAt = values?.contentModificationDate
            // Carpetas: se perfila el contenido sin leer texto (rápido) para diferenciarlas en la
            // lista («carpeta · N fichero(s) · dominante .ext») y usar su señal real al sugerir,
            // igual que hace el archivado (nombre → extensión dominante).
            var folderSummary: String?
            var dominantExtension: String?
            if isDirectory {
                let summary = FolderProfiler.summarize(folderURL: url, includeText: false)
                dominantExtension = summary.dominantExtension
                if summary.isEmpty {
                    folderSummary = "sin ficheros (cáscara vacía)"
                } else if let dominantExtension {
                    folderSummary = "\(summary.fileCount) fichero(s) · dominante .\(dominantExtension)"
                } else {
                    folderSummary = "\(summary.fileCount) fichero(s)"
                }
            }
            let suggestion = isDirectory
                ? RulesFilingClassifier.classifyFolder(name: name, dominantExtension: dominantExtension)?.categoryPath
                : RulesFilingClassifier.suggestDestination(fileName: name)?.categoryPath
            // Caché persistente: si ya se consultó a la IA este mismo archivo con la misma skill,
            // la propuesta reaparece sin volver a preguntar (sin gastar tokens).
            if aiSuggestions[url.path] == nil,
               let stored = suggestionStore.suggestion(forPath: url.path, sizeBytes: sizeBytes, modifiedAt: modifiedAt) {
                aiSuggestions[url.path] = stored
            }
            let ai = aiSuggestions[url.path]
            loaded.append(
                Item(
                    path: url.path,
                    name: name,
                    sizeBytes: sizeBytes,
                    modifiedAt: modifiedAt,
                    suggestion: suggestion,
                    destination: Self.effectiveDestination(
                        aiCategory: ai?.categoryPath,
                        aiIsQuarantine: ai?.isQuarantine ?? true,
                        rulesSuggestion: suggestion
                    ),
                    isDirectory: isDirectory,
                    folderSummary: folderSummary
                )
            )
        }
        let alive = Set(loaded.map(\.path))
        aiSuggestions = aiSuggestions.filter { alive.contains($0.key) }
        items = Self.sorted(loaded, by: sortKey)
        selection = selection.intersection(Set(items.map(\.id)))
    }

    /// Grupos para el orden por extensión: primero CARPETAS (unidades completas, que no tienen
    /// extensión), después las extensiones alfabéticas y «sin extensión» (solo ficheros) al final.
    var extensionGroups: [ExtensionGroup] { Self.extensionGroups(from: items) }

    /// Agrupación pura (testeable): las carpetas van a su propio grupo para diferenciarlas de los
    /// ficheros sin extensión (antes se mezclaban bajo «SIN EXTENSIÓN»).
    nonisolated static func extensionGroups(from items: [Item]) -> [ExtensionGroup] {
        let folders = items
            .filter(\.isDirectory)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let grouped = Dictionary(grouping: items.filter { !$0.isDirectory }) { item in
            (item.name as NSString).pathExtension.lowercased()
        }
        var groups: [ExtensionGroup] = []
        if !folders.isEmpty {
            groups.append(ExtensionGroup(key: "__folders__", title: "CARPETAS (\(folders.count))", items: folders))
        }
        groups.append(contentsOf: grouped.keys
            .sorted { a, b in
                if a.isEmpty != b.isEmpty { return !a.isEmpty }
                return a < b
            }
            .map { key in
                let list = (grouped[key] ?? []).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                return ExtensionGroup(
                    key: key,
                    title: "\(key.isEmpty ? "SIN EXTENSIÓN" : key.uppercased()) (\(list.count))",
                    items: list
                )
            })
        return groups
    }

    /// Destino común de la selección (nil si está mixta o si algún fichero no tiene destino).
    var selectionDestination: String? {
        let selected = items.filter { selection.contains($0.id) }
        guard !selected.isEmpty else { return nil }
        guard selected.allSatisfy({ $0.destination?.isEmpty == false }) else { return nil }
        let distinct = Set(selected.compactMap(\.destination))
        return distinct.count == 1 ? distinct.first : nil
    }

    var canMoveSelection: Bool {
        guard busyPaths.isEmpty else { return false }
        return items.contains { selection.contains($0.id) && $0.destination?.isEmpty == false }
    }

    var canTrashSelection: Bool {
        guard busyPaths.isEmpty else { return false }
        return items.contains { selection.contains($0.id) }
    }

    func selectAll() {
        selection = Set(items.map(\.id))
    }

    func setDestination(_ destination: String?, for id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].destination = destination
    }

    /// Aplica el destino elegido a todos los seleccionados (uno común para toda la selección).
    func setDestinationForSelection(_ destination: String?) {
        guard let destination, !destination.isEmpty else { return }
        for index in items.indices where selection.contains(items[index].id) {
            items[index].destination = destination
        }
    }

    private func applySort() {
        items = Self.sorted(items, by: sortKey)
    }

    /// Ordenación pura (testeable): ext (sin extensión al final) → nombre; nombre; fecha (recientes
    /// primero); tamaño (mayores primero).
    nonisolated static func sorted(_ items: [Item], by key: SortKey) -> [Item] {
        switch key {
        case .name:
            return items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .ext:
            return items.sorted {
                let a = ($0.name as NSString).pathExtension.lowercased()
                let b = ($1.name as NSString).pathExtension.lowercased()
                if a.isEmpty != b.isEmpty { return !a.isEmpty }
                if a != b { return a < b }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        case .date:
            return items.sorted { ($0.modifiedAt ?? .distantPast) > ($1.modifiedAt ?? .distantPast) }
        case .size:
            return items.sorted { $0.sizeBytes > $1.sizeBytes }
        }
    }

    /// Destino efectivo de una fila: la propuesta de la IA tiene prioridad sobre la sugerencia de
    /// reglas y **se conserva al recargar la lista** tras cada movimiento (antes se perdía del
    /// desplegable y había que rebuscarla). «Sin destino claro» (cuarentena) cae a la sugerencia local.
    nonisolated static func effectiveDestination(aiCategory: String?, aiIsQuarantine: Bool, rulesSuggestion: String?) -> String? {
        if let aiCategory, !aiIsQuarantine, !aiCategory.isEmpty {
            return aiCategory
        }
        return rulesSuggestion
    }

    /// Mueve un fichero a la categoría elegida (journal + undo + índice al momento).
    func move(_ item: Item) {
        performMove([item])
    }

    /// Mueve todos los ficheros seleccionados, cada uno a su destino elegido (por defecto, la
    /// sugerencia de las reglas). Los que no tengan destino se omiten con aviso.
    func moveSelected() {
        performMove(items.filter { selection.contains($0.id) })
    }

    /// Nº de elementos con propuesta accionable de la IA (para el botón «Mover sugeridos»).
    var suggestedCount: Int {
        items.reduce(into: 0) { count, item in
            if let ai = aiSuggestions[item.id], !ai.isQuarantine, !ai.categoryPath.isEmpty {
                count += 1
            }
        }
    }

    /// Mueve de una vez todos los elementos con propuesta de la IA (los «sin destino claro» se quedan).
    /// Fija el destino de cada uno a la propuesta antes del movimiento (aunque el desplegable se
    /// hubiera desincronizado).
    func moveAllSuggested() {
        guard !reevaluating else { return }
        var ready: [Item] = []
        for index in items.indices {
            guard let ai = aiSuggestions[items[index].id], !ai.isQuarantine, !ai.categoryPath.isEmpty else { continue }
            items[index].destination = ai.categoryPath
            ready.append(items[index])
        }
        guard !ready.isEmpty else {
            errorMessage = "No hay propuestas de la IA para mover (pulsa «Reevaluar con IA»)."
            return
        }
        performMove(ready)
    }

    /// Olvida la propuesta de la IA (memoria + caché en disco): la próxima «Reevaluar»
    /// volverá a preguntar al modelo para este elemento.
    func forgetAISuggestion(_ item: Item) {
        aiSuggestions.removeValue(forKey: item.id)
        suggestionStore.remove(forPath: item.id)
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx].destination = items[idx].suggestion
        }
        statusMessage = "Propuesta olvidada para «\(item.name)»; «Reevaluar con IA» la volverá a consultar."
    }

    /// Desglosa una carpeta-cajón (acción explícita del menú contextual): cada elemento se clasifica
    /// por separado (journal en un mismo lote) y la cáscara vacía queda en origen.
    func splitFolder(_ item: Item) {
        guard item.isDirectory, let rootPath, !busyPaths.contains(item.path) else { return }
        busyPaths.insert(item.path)
        statusMessage = "Desglosando «\(item.name)»…"
        errorMessage = nil
        Task {
            let coordinator = FilingCoordinator(
                index: index,
                rootURL: URL(fileURLWithPath: rootPath, isDirectory: true)
            )
            let outcome = await coordinator.splitFolder(at: URL(fileURLWithPath: item.path))
            busyPaths.remove(item.path)
            aiSuggestions.removeValue(forKey: item.id)
            suggestionStore.remove(forPath: item.id)
            if outcome.action == "split" {
                statusMessage = "«\(item.name)»: \(outcome.reason)"
            } else {
                errorMessage = "No se pudo desglosar «\(item.name)»: \(outcome.reason)"
            }
            load()
        }
    }

    /// Reevalúa con la IA (skill actual) los elementos seleccionados — o todos si no hay selección —
    /// y deja la propuesta como destino sugerido (el movimiento sigue siendo explícito con «Mover»).
    func reevaluateWithAI() {
        guard let rootPath, !reevaluating else { return }
        let targets = selection.isEmpty ? items : items.filter { selection.contains($0.id) }
        guard !targets.isEmpty else { return }
        reevaluating = true
        errorMessage = nil
        Task {
            let coordinator = FilingCoordinator(
                index: index,
                rootURL: URL(fileURLWithPath: rootPath, isDirectory: true),
                advisor: DeepSeekFilingAdvisor()
            )
            var done = 0
            var withDestination = 0
            var reusedFromCache = 0
            for item in targets {
                statusMessage = "Reevaluando con IA… \(done)/\(targets.count)"
                // 1) Caché persistente: misma pregunta + mismo archivo + misma skill → sin coste.
                let suggestion: FilingCoordinator.Suggestion?
                if let cached = suggestionStore.suggestion(forPath: item.path, sizeBytes: item.sizeBytes, modifiedAt: item.modifiedAt) {
                    suggestion = cached
                    reusedFromCache += 1
                } else {
                    suggestion = await coordinator.proposeDestination(for: URL(fileURLWithPath: item.path))
                    // 2) Solo se guardan propuestas realmente de la IA (las de reglas no necesitan caché).
                    if let fresh = suggestion, fresh.source == .ai {
                        suggestionStore.store(fresh, forPath: item.path, sizeBytes: item.sizeBytes, modifiedAt: item.modifiedAt)
                    }
                }
                if let suggestion {
                    aiSuggestions[item.path] = suggestion
                    if let idx = items.firstIndex(where: { $0.id == item.path }), !suggestion.isQuarantine, !suggestion.categoryPath.isEmpty {
                        items[idx].destination = suggestion.categoryPath
                        withDestination += 1
                    }
                }
                done += 1
            }
            var message = "Reevaluados \(done) elemento(s) (skill v\(FilingSkill.version)): \(withDestination) con destino propuesto"
            if reusedFromCache > 0 {
                message += " · \(reusedFromCache) reutilizados de la caché (sin gastar tokens)"
            }
            statusMessage = message + "."
            reevaluating = false
        }
    }

    /// Mueve los seleccionados a la Papelera (acción manual y reversible desde el Finder; no pasa
    /// por el journal porque no es un archivado — el guardrail se mantiene: nunca se borra).
    func trashSelected() {
        performTrash(items.filter { selection.contains($0.id) })
    }

    /// Mueve un solo fichero a la Papelera (menú contextual de la fila).
    func trash(_ item: Item) {
        performTrash([item])
    }

    private func performMove(_ targets: [Item]) {
        guard let rootPath, !targets.isEmpty else { return }
        let ready = targets.filter { $0.destination?.isEmpty == false }
        let skipped = targets.count - ready.count
        guard !ready.isEmpty else {
            errorMessage = "Los ficheros seleccionados no tienen destino elegido."
            return
        }
        for item in ready {
            busyPaths.insert(item.path)
        }
        statusMessage = nil
        errorMessage = nil
        Task {
            let coordinator = FilingCoordinator(
                index: index,
                rootURL: URL(fileURLWithPath: rootPath, isDirectory: true)
            )
            var movedCount = 0
            var firstDetail: String?
            var failures: [String] = []
            for item in ready {
                let outcome = await coordinator.reclassify(fileAt: URL(fileURLWithPath: item.path), to: item.destination ?? "")
                busyPaths.remove(item.path)
                if outcome.action == "move" {
                    movedCount += 1
                    suggestionStore.remove(forPath: item.path)
                    if firstDetail == nil {
                        let finalName = (outcome.destinationPath as NSString).lastPathComponent
                        var detail = "«\(item.name)» → \(outcome.categoryPath)"
                        if finalName != item.name {
                            detail += " (guardado como «\(finalName)» para no sobrescribir)"
                        }
                        firstDetail = detail
                    }
                } else {
                    failures.append("«\(item.name)»")
                }
            }
            if ready.count == 1 {
                statusMessage = firstDetail
            } else {
                var message = "Movidos \(movedCount) de \(ready.count)"
                if skipped > 0 { message += " · \(skipped) sin destino (omitidos)" }
                if !failures.isEmpty {
                    message += " · errores: \(failures.prefix(3).joined(separator: ", "))\(failures.count > 3 ? "…" : "")"
                }
                statusMessage = message
            }
            if movedCount == 0 {
                errorMessage = "No se pudo mover: \(failures.prefix(3).joined(separator: ", "))"
            }
            load()
        }
    }

    private func performTrash(_ targets: [Item]) {
        guard !targets.isEmpty else { return }
        statusMessage = nil
        errorMessage = nil
        let fileManager = FileManager.default
        var trashed: [Item] = []
        var failures: [String] = []
        for item in targets {
            guard fileManager.fileExists(atPath: item.path) else {
                failures.append("«\(item.name)» (ya no existe)")
                continue
            }
            do {
                try fileManager.trashItem(at: URL(fileURLWithPath: item.path), resultingItemURL: nil)
                trashed.append(item)
                suggestionStore.remove(forPath: item.path)
                J4Log.info(.app, "Papelera: «\(item.name)» movido a la papelera desde «Por revisar».")
            } catch {
                failures.append("«\(item.name)»")
            }
        }
        guard !trashed.isEmpty else {
            errorMessage = "No se pudo mover a la papelera: \(failures.prefix(3).joined(separator: ", "))"
            return
        }
        let paths = trashed.map(\.path)
        Task {
            for path in paths {
                if let root = try? await index.rootID(containing: path) {
                    _ = try? await index.removeEntries(rootID: root.id, paths: [path])
                }
            }
            if trashed.count == 1, let only = trashed.first {
                statusMessage = "«\(only.name)» → Papelera"
            } else {
                var message = "\(trashed.count) fichero(s) → Papelera"
                if !failures.isEmpty {
                    message += " · errores: \(failures.prefix(3).joined(separator: ", "))\(failures.count > 3 ? "…" : "")"
                }
                statusMessage = message
            }
            load()
        }
    }

    func revealQuarantine() {
        guard let quarantineURL else { return }
        guard FileManager.default.fileExists(atPath: quarantineURL.path) else {
            errorMessage = "Todavía no existe la carpeta de cuarentena."
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([quarantineURL])
    }
}
