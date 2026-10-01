import AppKit
import LifeOSAPI
import LifeOSCore
import SwiftUI

/// Diagnóstico del servidor, dentro de la app.
///
/// Es el mismo que corre `lifeos-doctor` en la terminal, pero aquí usa la sesión
/// que la app ya tiene: sirve para ver **por qué** una pantalla no funciona
/// contra un servidor que no es el de desarrollo. Deja un informe en disco (sin
/// la sesión dentro) para poder enseñarlo tal cual.
struct DoctorCard: View {
    @ObservedObject var model: LifeOSModel

    var body: some View {
        VStack(alignment: .leading, spacing: LifeOSSpace.s) {
            LifeOSSectionHeader("Diagnóstico del servidor", count: model.doctorChecks.count)
            LifeOSCard {
                VStack(alignment: .leading, spacing: LifeOSSpace.m) {
                    Text("Comprueba la dirección, la salud del servidor, qué endpoints tiene, si tu sesión vale ahí y si cada pantalla se entiende (el JSON encaja con lo que la app espera).")
                        .font(LifeOSFont.bodySmall)
                        .foregroundStyle(LifeOSTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: LifeOSSpace.s) {
                        Button {
                            Task { await model.runDoctor() }
                        } label: {
                            Label("Comprobar ahora", systemImage: "stethoscope")
                        }
                        .buttonStyle(LifeOSSecondaryButtonStyle())
                        .disabled(model.doctorRunning)

                        if model.doctorRunning {
                            ProgressView().controlSize(.small)
                        }

                        Spacer(minLength: 0)

                        if let report = model.doctorReport {
                            Button("Ver el informe") {
                                NSWorkspace.shared.activateFileViewerSelecting([report])
                            }
                            .buttonStyle(LifeOSGhostButtonStyle())
                            .help(report.path)
                        }
                    }

                    if !model.doctorChecks.isEmpty {
                        LifeOSDivider()
                        VStack(alignment: .leading, spacing: LifeOSSpace.s) {
                            ForEach(model.doctorChecks) { check in
                                row(check)
                            }
                        }
                        Text(summary)
                            .font(LifeOSFont.caption)
                            .foregroundStyle(LifeOSTheme.textTertiary)
                    }
                }
            }
        }
    }

    private var summary: String {
        let server = model.serverText
        let report = model.doctorReport.map { " Informe en \($0.path)" } ?? ""
        return "Servidor: \(server).\(report)"
    }

    private func row(_ check: DoctorCheck) -> some View {
        HStack(alignment: .top, spacing: LifeOSSpace.s) {
            Text(check.level.symbol)
                .font(LifeOSFont.label)
                .foregroundStyle(color(for: check.level))
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(check.title)
                    .font(LifeOSFont.bodySmall)
                    .foregroundStyle(LifeOSTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(check.detail)
                    .font(LifeOSFont.caption)
                    .foregroundStyle(LifeOSTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func color(for level: DoctorCheck.Level) -> Color {
        switch level {
        case .ok: return LifeOSTheme.positive
        case .warning: return LifeOSTheme.warning
        case .failure: return LifeOSTheme.danger
        }
    }
}
