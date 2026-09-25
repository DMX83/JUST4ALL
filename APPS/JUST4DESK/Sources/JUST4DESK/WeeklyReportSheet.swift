import AppKit
import SwiftUI
import J4ICore
import J4IFiling

/// G6 — Hoja del informe semanal: KPIs de los últimos 7 días, copiable y exportable en Markdown.
struct WeeklyReportSheet: View {
    @ObservedObject var viewModel: SearchViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var report: WeeklyReport?
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: J4I.Space.m) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(J4I.brand)
                Text("Informe semanal")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Spacer()
            }
            Text("Local y exportable: archivados, datos ordenados, categorías top, reglas promovidas y ahorro estimado de tokens por conocimiento local.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let report {
                ScrollView {
                    Text(report.markdown)
                        .font(.system(size: 11.5, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(J4I.Space.m)
                }
                .background(
                    RoundedRectangle(cornerRadius: J4I.Radius.medium, style: .continuous)
                        .fill(J4I.well)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: J4I.Radius.medium, style: .continuous)
                        .strokeBorder(J4I.hairline.opacity(0.6))
                )
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Calculando…")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            HStack(spacing: 8) {
                if copied {
                    Text("Copiado al portapapeles")
                        .font(.system(size: 11))
                        .foregroundStyle(J4I.success)
                }
                Spacer()
                Button("Copiar") {
                    guard let report else { return }
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(report.markdown, forType: .string)
                    copied = true
                }
                .disabled(report == nil)
                Button("Exportar…") {
                    export()
                }
                .disabled(report == nil)
                Button("Cerrar") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(J4I.Space.l)
        .frame(width: 680, height: 560)
        .task {
            report = await viewModel.buildWeeklyReport()
        }
    }

    private func export() {
        guard let report else { return }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let panel = NSSavePanel()
        panel.title = "Exportar informe semanal"
        panel.nameFieldStringValue = "just4desk-informe-\(formatter.string(from: report.generatedAt)).md"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(report.markdown.utf8).write(to: url)
            J4Log.info(.app, "Informe semanal exportado a «\(url.path)».")
        } catch {
            J4Log.warn(.app, "No se pudo exportar el informe: \(error.localizedDescription)")
        }
    }
}
