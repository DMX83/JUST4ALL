import SwiftUI
import J4IIndex

/// Actividad de organización: journal de archivados con undo y acciones.
struct FilingActivitySheet: View {
    @ObservedObject var viewModel: SearchViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Actividad de organización")
                    .font(.title3.bold())
                if viewModel.simulationMode {
                    Text("SIMULACIÓN")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.orange.opacity(0.25)))
                }
                Spacer()
                Button("Deshacer el último") {
                    viewModel.undoLast()
                }
                .disabled(viewModel.activityEntries.first(where: { $0.isUndoable }) == nil)
                Button("Cerrar") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            if viewModel.activityEntries.isEmpty {
                Text("Todavía no hay actividad. Los documentos que lleguen a la carpeta vigilada aparecerán aquí.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                List(viewModel.activityEntries) { entry in
                    row(for: entry)
                }
                .listStyle(.inset)
            }
        }
        .padding(20)
        .frame(width: 680, height: 440)
        .task {
            await viewModel.refreshActivity()
        }
    }

    private func row(for entry: JournalEntry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: iconName(for: entry))
                .foregroundStyle(iconColor(for: entry))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.fileName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    Text(entry.categoryPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if entry.action == "simulate" {
                        tag("simulado", color: .orange)
                    }
                    if entry.state == "undone" {
                        tag("deshecho", color: .secondary)
                    }
                }
            }
            Spacer()
            if entry.isUndoable {
                Button("Deshacer") {
                    viewModel.undo(entry: entry)
                }
            }
            Button("Mostrar") {
                viewModel.revealPath(entry.destinationPath)
            }
        }
        .padding(.vertical, 2)
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(0.18)))
    }

    private func iconName(for entry: JournalEntry) -> String {
        switch entry.action {
        case "move": return "tray.and.arrow.down"
        case "quarantine": return "questionmark.folder"
        case "simulate": return "eye"
        case "skipped-duplicate": return "doc.on.doc"
        default: return "exclamationmark.triangle"
        }
    }

    private func iconColor(for entry: JournalEntry) -> Color {
        switch entry.action {
        case "move": return .green
        case "quarantine": return .orange
        case "simulate": return .blue
        case "skipped-duplicate": return .secondary
        default: return .red
        }
    }
}
