import SwiftUI
import AppKit
import J4ICore

/// Configuración inicial (primer arranque): elige/crea la carpeta raíz de la organización
/// y genera el esqueleto de taxonomía dentro.
struct InitialSetupSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onComplete: (String, String) -> Void

    @State private var rootPath: String
    @State private var sourcePath: String
    @State private var errorMessage: String?

    init(initialPath: String, initialSourcePath: String, onComplete: @escaping (String, String) -> Void) {
        self.onComplete = onComplete
        _rootPath = State(initialValue: initialPath)
        _sourcePath = State(initialValue: initialSourcePath)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Configura tu organización de documentos")
                .font(.title2.bold())
            Text("JUST4DESK archivará automáticamente tus documentos dentro de esta carpeta, ordenados por categorías. Podrás cambiarla más adelante desde el menú «Carpetas».")
                .foregroundStyle(.secondary)

            Text("Carpeta raíz de la organización")
                .font(.callout.bold())
            HStack(spacing: 8) {
                TextField("Carpeta raíz", text: $rootPath)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                Button("Elegir…") {
                    chooseFolder(forRoot: true)
                }
            }

            Text("Carpeta de entrada (los documentos nuevos se archivarán automáticamente)")
                .font(.callout.bold())
            HStack(spacing: 8) {
                TextField("Carpeta de entrada", text: $sourcePath)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                Button("Elegir…") {
                    chooseFolder(forRoot: false)
                }
            }

            GroupBox("Se crearán estas carpetas (\(previewLines.count))") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(previewLines, id: \.self) { line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(6)
                }
                .frame(height: 190)
                .frame(maxWidth: .infinity)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Ahora no") {
                    dismiss()
                }
                Spacer()
                Button("Crear estructura") {
                    install()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedRootPath.isEmpty || trimmedSourcePath.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    // MARK: - Helpers

    private var trimmedRootPath: String {
        rootPath.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedSourcePath: String {
        sourcePath.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var previewLines: [String] {
        DefaultTaxonomy.categories().flatMap { node in
            [node.name] + node.children.map { "    \($0.name)" }
        }
    }

    private func chooseFolder(forRoot: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Usar esta carpeta"
        panel.message = forRoot
            ? "Elige dónde crear (o reutilizar) la carpeta de organización"
            : "Elige la carpeta de entrada que se vigilará (por ejemplo, Descargas)"
        if panel.runModal() == .OK, let url = panel.url {
            if forRoot {
                rootPath = url.path
            } else {
                sourcePath = url.path
            }
        }
    }

    private func install() {
        let expanded = (trimmedRootPath as NSString).expandingTildeInPath
        let rootURL = URL(fileURLWithPath: expanded, isDirectory: true)
        let report = TaxonomyInstaller.install(at: rootURL)

        guard report.conflicts.isEmpty else {
            let sample = report.conflicts.prefix(3).joined(separator: ", ")
            errorMessage = "No se pudieron crear \(report.conflicts.count) carpeta(s) (\(sample)…). Comprueba permisos o elige otra ubicación."
            return
        }
        let expandedSource = (trimmedSourcePath as NSString).expandingTildeInPath
        let sourceURL = URL(fileURLWithPath: expandedSource, isDirectory: true)
        onComplete(rootURL.standardizedFileURL.path, sourceURL.standardizedFileURL.path)
        dismiss()
    }
}
