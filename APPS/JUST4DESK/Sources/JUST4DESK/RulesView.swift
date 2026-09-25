import AppKit
import SwiftUI
import J4ICore
import J4IFiling

/// G3 — Pantalla «Reglas»: el conocimiento local a la vista y bajo control.
///
/// Muestra las características observadas (extensiones y palabras de carpeta) — promovidas o aún
/// en observación — con confianza y muestras. Permite **cambiar el destino**, **borrar**, **crear
/// reglas a mano** y **exportar/importar** (portabilidad entre Macs). Las reglas se aplican solas
/// en la clasificación (sin llamar a la IA); esta ventana existe para revisarlas y gobernarlas.
struct RulesView: View {
    @StateObject private var model = RulesViewModel()
    @State private var chooserRuleID: String?
    @State private var showNewRule = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if model.rules.isEmpty {
                emptyState
            } else {
                rulesList
            }
            Divider()
            statusBar
        }
        .frame(minWidth: 660, minHeight: 460)
        .task { model.load() }
        .sheet(isPresented: $showNewRule) {
            NewRuleSheet(model: model)
        }
    }

    // MARK: - Cabecera

    private var toolbar: some View {
        HStack(spacing: J4I.Space.s) {
            HStack(spacing: 6) {
                Image(systemName: "text.badge.checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(J4I.brand)
                Text("Reglas")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("\(model.rules.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.primary.opacity(0.07)))
            }
            Spacer(minLength: J4I.Space.s)
            Button {
                showNewRule = true
            } label: {
                Label("Nueva regla", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .help("Crea una regla manual: la app la aplicará sin preguntar a la IA")
            Button {
                model.exportRules()
            } label: {
                Label("Exportar…", systemImage: "square.and.arrow.up")
            }
            .disabled(model.rules.isEmpty)
            .help("Guarda las reglas en un JSON portable (otro Mac o copia de seguridad)")
            Button {
                model.importRules()
            } label: {
                Label("Importar…", systemImage: "square.and.arrow.down")
            }
            .help("Fusiona las reglas de un JSON exportado (gana la entrada con más muestras)")
            Menu {
                Button("Actualizar lista") { model.load() }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 24, height: 20)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .controlSize(.small)
        .padding(.horizontal, J4I.Space.m)
        .padding(.vertical, 8)
    }

    // MARK: - Lista

    private var rulesList: some View {
        List {
            if !model.folderRules.isEmpty {
                Section(header: Text("PALABRAS DE CARPETA (\(model.folderRules.count))")) {
                    ForEach(model.folderRules) { rule in
                        rowView(for: rule)
                    }
                }
            }
            if !model.extensionRules.isEmpty {
                Section(header: Text("EXTENSIONES (\(model.extensionRules.count))")) {
                    ForEach(model.extensionRules) { rule in
                        rowView(for: rule)
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private func rowView(for rule: LocalKnowledgeStore.RuleInfo) -> some View {
        HStack(spacing: 10) {
            Image(systemName: rule.kind == .fileExtension ? "doc" : "folder")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(rule.isPromoted ? J4I.brand : Color.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(rule.displayValue)
                        .font(.system(size: 12.5, weight: .medium, design: rule.kind == .fileExtension ? .monospaced : .default))
                        .lineLimit(1)
                    stateBadge(rule)
                }
                Text(subtitle(for: rule))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            Button {
                chooserRuleID = rule.id
            } label: {
                HStack(spacing: 4) {
                    Text(rule.categoryPath.isEmpty ? "Elegir destino…" : rule.categoryPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                }
                .frame(width: 220, alignment: .leading)
            }
            .controlSize(.small)
            .help("Cambia el destino: la regla se reescribe al momento")
            .popover(isPresented: Binding(
                get: { chooserRuleID == rule.id },
                set: { if !$0 { chooserRuleID = nil } }
            ), arrowEdge: .bottom) {
                DestinationChooser(
                    title: "Destino para «\(rule.displayValue)»",
                    destinations: model.destinations,
                    onSelect: { destination in
                        model.setDestination(destination, for: rule)
                        chooserRuleID = nil
                    },
                    onCancel: { chooserRuleID = nil },
                    onCreate: { name in
                        model.setDestination(name, for: rule)
                        chooserRuleID = nil
                    }
                )
            }
        }
        .padding(.vertical, 3)
        .hoverHighlight(intensity: 0.05)
        .contextMenu {
            Button("Cambiar destino…") {
                chooserRuleID = rule.id
            }
            Divider()
            Button("Borrar regla", role: .destructive) {
                model.remove(rule)
            }
        }
    }

    private func stateBadge(_ rule: LocalKnowledgeStore.RuleInfo) -> some View {
        let tint: Color = rule.isPromoted ? J4I.success : .secondary
        return Text(rule.isPromoted ? "PROMOVIDA" : "OBSERVANDO")
            .font(.system(size: 9, weight: .semibold))
            .kerning(0.4)
            .foregroundStyle(tint)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(tint.opacity(0.14)))
    }

    private func subtitle(for rule: LocalKnowledgeStore.RuleInfo) -> String {
        var parts: [String] = []
        if rule.isPromoted {
            parts.append("\(Int((rule.averageConfidence * 100).rounded())) % confianza")
        }
        parts.append("\(rule.positives)/\(rule.total) muestra(s)")
        parts.append("vista \(rule.lastSeen.formatted(.relative(presentation: .named)))")
        return parts.joined(separator: " · ")
    }

    private var emptyState: some View {
        J4IEmptyState(
            systemImage: "text.badge.checkmark",
            title: "Sin reglas todavía",
            message: "Cuando la misma característica (una extensión, una palabra de carpeta) se repita en los aciertos de la IA o en tus correcciones, aparecerá aquí — podrás editarla, borrarla, exportarla o crear una a mano.",
            tint: J4I.brand
        )
    }

    // MARK: - Barra de estado

    private var statusBar: some View {
        HStack(spacing: 10) {
            if let error = model.errorMessage {
                Text(error)
                    .foregroundStyle(J4I.danger)
            } else if let status = model.statusMessage {
                Text(status)
                    .foregroundStyle(.secondary)
            } else {
                let stats = model.stats
                Text("\(stats.promotedCount) promovida(s) · \(stats.learnedEntries) característica(s) observada(s) · aplicadas hoy \(stats.appliedToday) (total \(stats.appliedTotal))")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .font(.system(size: 11))
        .lineLimit(1)
        .truncationMode(.middle)
        .padding(.horizontal, J4I.Space.m)
        .padding(.vertical, 7)
    }
}

/// Estado de la pantalla «Reglas»: lista del conocimiento local + acciones de gestión.
@MainActor
final class RulesViewModel: ObservableObject {
    @Published private(set) var rules: [LocalKnowledgeStore.RuleInfo] = []
    @Published private(set) var destinations: [String] = []
    @Published var statusMessage: String?
    @Published var errorMessage: String?
    @Published private(set) var stats = LocalKnowledgeStore.Stats(promotedCount: 0, learnedEntries: 0, appliedToday: 0, appliedTotal: 0)

    private let store = LocalKnowledgeStore.shared

    var extensionRules: [LocalKnowledgeStore.RuleInfo] { rules.filter { $0.kind == .fileExtension } }
    var folderRules: [LocalKnowledgeStore.RuleInfo] { rules.filter { $0.kind == .folderToken } }

    func load() {
        rules = store.rules()
        stats = store.stats()
        if let rootPath = FilingConfiguration.rootPath {
            destinations = TaxonomyInventory.availableDestinations(rootURL: URL(fileURLWithPath: rootPath, isDirectory: true))
        } else {
            destinations = DefaultTaxonomy.allRelativePaths.filter { $0 != DefaultTaxonomy.quarantineRelativePath }
        }
    }

    func setDestination(_ destination: String, for rule: LocalKnowledgeStore.RuleInfo) {
        store.setDestination(destination, kind: rule.kind, value: rule.value)
        J4Log.info(.ai, "Regla actualizada a mano: «\(rule.displayValue)» → «\(destination)».")
        statusMessage = "«\(rule.displayValue)» → «\(destination)» (la IA ya no decidirá esta característica)."
        load()
    }

    func remove(_ rule: LocalKnowledgeStore.RuleInfo) {
        if store.removeRule(kind: rule.kind, value: rule.value) {
            J4Log.info(.ai, "Regla borrada a mano: «\(rule.displayValue)».")
            statusMessage = "Regla «\(rule.displayValue)» borrada — la IA volverá a decidir para esta característica."
        }
        load()
    }

    func addManual(kind: LocalKnowledgeStore.FeatureKind, value: String, destination: String) {
        store.addManualRule(kind: kind, value: value, categoryPath: destination)
        J4Log.info(.ai, "Regla manual creada: «\(value)» (\(kind.rawValue)) → «\(destination)».")
        statusMessage = "Regla manual creada: «\(value)» → «\(destination)»."
        load()
    }

    func exportRules() {
        guard let data = store.exportData() else {
            errorMessage = "No se pudieron serializar las reglas."
            return
        }
        let panel = NSSavePanel()
        panel.title = "Exportar reglas de JUST4DESK"
        panel.message = "Se exportan \(rules.count) característica(s) observadas (JSON portable v1)."
        panel.nameFieldStringValue = "just4desk-reglas.json"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url)
            statusMessage = "Reglas exportadas a «\(url.lastPathComponent)»."
            J4Log.info(.ai, "Reglas exportadas a «\(url.path)».")
        } catch {
            errorMessage = "No se pudo escribir el archivo: \(error.localizedDescription)"
        }
    }

    func importRules() {
        let panel = NSOpenPanel()
        panel.title = "Importar reglas en JUST4DESK"
        panel.message = "Se fusionan con las actuales: gana la entrada con más muestras (lo aprendido aquí no se pierde)."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
        guard let report = store.importData(data) else {
            errorMessage = "El archivo no es un export de reglas de JUST4DESK."
            return
        }
        J4Log.info(.ai, "Reglas importadas desde «\(url.path)»: +\(report.added), ~\(report.replaced), =\(report.kept).")
        statusMessage = report.summary
        load()
    }
}

/// Formulario de regla manual (G3): característica + destino.
struct NewRuleSheet: View {
    @ObservedObject var model: RulesViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var kind: LocalKnowledgeStore.FeatureKind = .fileExtension
    @State private var value = ""
    @State private var destination = ""
    @State private var showChooser = false

    var body: some View {
        VStack(alignment: .leading, spacing: J4I.Space.m) {
            Text("Nueva regla")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            Text("Se aplicará sin preguntar a la IA: la app clasificará así las próximas coincidencias.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Picker("Tipo", selection: $kind) {
                    Text("Extensión de archivo").tag(LocalKnowledgeStore.FeatureKind.fileExtension)
                    Text("Palabra del nombre de carpeta").tag(LocalKnowledgeStore.FeatureKind.folderToken)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                HStack(spacing: 8) {
                    Text(kind == .fileExtension ? "Extensión:" : "Palabra:")
                        .font(.system(size: 12))
                        .frame(width: 74, alignment: .leading)
                    TextField(kind == .fileExtension ? "rsc" : "trading", text: $value)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                }
                HStack(spacing: 8) {
                    Text("Destino:")
                        .font(.system(size: 12))
                        .frame(width: 74, alignment: .leading)
                    Button {
                        showChooser = true
                    } label: {
                        Text(destination.isEmpty ? "Elegir destino…" : destination)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(width: 300, alignment: .leading)
                    }
                    .popover(isPresented: $showChooser, arrowEdge: .bottom) {
                        DestinationChooser(
                            title: "Destino para la nueva regla",
                            destinations: model.destinations,
                            onSelect: { picked in
                                destination = picked
                                showChooser = false
                            },
                            onCancel: { showChooser = false },
                            onCreate: { name in
                                destination = name
                                showChooser = false
                            }
                        )
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }
                Button("Crear regla") {
                    model.addManual(kind: kind, value: value, destination: destination)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || destination.isEmpty)
            }
        }
        .padding(J4I.Space.l)
        .frame(width: 470)
    }
}
