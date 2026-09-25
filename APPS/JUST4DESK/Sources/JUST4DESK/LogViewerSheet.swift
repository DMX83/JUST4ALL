import AppKit
import SwiftUI
import J4ICore

/// Visor del registro en vivo de JUST4DESK.
///
/// - Muestra el historial (`J4Log.entries`) y se suscribe al stream en vivo (`J4Log.stream()`).
/// - Filtros por nivel mínimo, categoría y texto libre; «Seguir» activa el auto-scroll.
/// - Acciones: copiar lo filtrado, limpiar el buffer en memoria y revelar el archivo de registro.
struct LogViewerSheet: View {
    @StateObject private var model = LogViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            filterBar
            Divider()
            logList
        }
        .frame(minWidth: 760, minHeight: 480)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    // MARK: - Cabecera

    private var header: some View {
        HStack(spacing: 10) {
            Label("Registro de actividad", systemImage: "text.alignleft")
                .font(.headline)
            Text("\(model.filteredEntries.count) de \(model.entries.count) entradas")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Toggle(isOn: $model.follow) {
                Text("Seguir")
                    .font(.caption)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .help("Desplazarse automáticamente a las entradas nuevas")
            Button("Copiar") { copyFilteredToPasteboard() }
                .disabled(model.filteredEntries.isEmpty)
                .help("Copiar las entradas filtradas al portapapeles")
            Button("Limpiar") { model.clear() }
                .disabled(model.entries.isEmpty)
                .help("Vaciar el historial en memoria (el archivo de registro se conserva)")
            if let logURL = J4Log.fileURL {
                Button("Revelar log") {
                    NSWorkspace.shared.activateFileViewerSelecting([logURL])
                }
                .help("Mostrar ~/Library/Logs/JUST4DESK/just4desk.log en Finder")
            }
            Button("Cerrar") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(12)
    }

    // MARK: - Filtros

    private var filterBar: some View {
        HStack(spacing: 10) {
            Picker("Nivel", selection: $model.minimumLevel) {
                Text("Todos los niveles").tag(J4LogLevel?.none)
                ForEach(J4LogLevel.allCases, id: \.self) { level in
                    Text("≥ \(level.label)").tag(J4LogLevel?.some(level))
                }
            }
            .frame(maxWidth: 190)

            Picker("Categoría", selection: $model.category) {
                Text("Todas las categorías").tag(J4LogCategory?.none)
                ForEach(J4LogCategory.allCases, id: \.self) { category in
                    Text(category.displayName).tag(J4LogCategory?.some(category))
                }
            }
            .frame(maxWidth: 210)

            TextField("Filtrar texto…", text: $model.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 240)

            Spacer()
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Lista

    @ViewBuilder
    private var logList: some View {
        if model.entries.isEmpty {
            ContentUnavailableView {
                Label("Sin entradas todavía", systemImage: "text.alignleft")
            } description: {
                Text("Aquí verás en vivo la actividad de búsqueda, indexado, ingesta y archivado.")
            }
        } else if model.filteredEntries.isEmpty {
            ContentUnavailableView {
                Label("Sin coincidencias", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("Ninguna entrada cumple los filtros actuales.")
            }
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(model.filteredEntries) { entry in
                            row(entry)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .defaultScrollAnchor(.bottom)
                .onChange(of: model.filteredEntries.count) { _, _ in
                    guard model.follow, let last = model.filteredEntries.last else { return }
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private func row(_ entry: J4LogEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(entry.date, format: .dateTime.hour().minute().second())
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            LogLevelBadge(level: entry.level)
            Text(entry.category.displayName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .leading)
            Text(entry.message)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .id(entry.id)
    }

    private func copyFilteredToPasteboard() {
        let text = model.filteredEntries
            .map { "[\($0.level.label)] [\($0.category.rawValue)] \($0.message)" }
            .joined(separator: "\n")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

/// Distintivo de color por nivel.
struct LogLevelBadge: View {
    let level: J4LogLevel

    var body: some View {
        Text(level.label)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(0.16)))
    }

    private var color: Color {
        switch level {
        case .debug: return .secondary
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }
}

/// Modelo del visor: historial + stream en vivo con filtros.
@MainActor
final class LogViewModel: ObservableObject {
    @Published var entries: [J4LogEntry] = []
    @Published var minimumLevel: J4LogLevel?
    @Published var category: J4LogCategory?
    @Published var searchText = ""
    @Published var follow = true

    private var task: Task<Void, Never>?

    var filteredEntries: [J4LogEntry] {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return entries.filter { entry in
            if let minimumLevel, entry.level < minimumLevel { return false }
            if let category, entry.category != category { return false }
            if !needle.isEmpty {
                let haystack = "\(entry.category.displayName) \(entry.message)".lowercased()
                if !haystack.contains(needle) { return false }
            }
            return true
        }
    }

    func start() {
        guard task == nil else { return }
        entries = J4Log.entries(limit: 2000)
        task = Task { [weak self] in
            for await entry in J4Log.stream() {
                guard let self, !Task.isCancelled else { return }
                self.entries.append(entry)
                if self.entries.count > 4000 {
                    self.entries.removeFirst(self.entries.count - 4000)
                }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    func clear() {
        J4Log.clearBuffer()
        entries = []
    }
}
