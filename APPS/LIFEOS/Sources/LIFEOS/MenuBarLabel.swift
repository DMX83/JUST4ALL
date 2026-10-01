import LifeOSUI
import SwiftUI

/// Lo que se ve en la barra de menús: la marca, un **anillo con lo cerrado que
/// está el día** y, si hay algo esperando, la cifra de capturas pendientes.
///
/// Las cifras salen del servidor tal cual (`day-close`); aquí no se calcula nada
/// para que el número de la barra y el de la app sean siempre el mismo. El anillo
/// sí es una proporción, y por eso lleva su propia regla: **cerradas sobre el
/// total del día**, y se queda lleno cuando no hay nada abierto (que es
/// justamente la situación en la que no hay nada que mirar).
struct MenuBarLabel: View {
    @ObservedObject var model: LifeOSModel

    var body: some View {
        HStack(spacing: 3) {
            ring
            if let pending, pending > 0 {
                Text("\(pending)")
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Anillo

    private var ring: some View {
        ZStack {
            Canvas { context, size in
                let grosor: CGFloat = 2
                let caja = CGRect(origin: .zero, size: size)
                    .insetBy(dx: grosor / 2 + 0.5, dy: grosor / 2 + 0.5)
                let centro = CGPoint(x: caja.midX, y: caja.midY)
                let radio = caja.width / 2

                // El carril se ve siempre, para que el anillo no «aparezca» y
                // desaparezca según el día.
                context.stroke(
                    Path(ellipseIn: caja),
                    with: .color(.secondary.opacity(0.35)),
                    lineWidth: grosor
                )
                guard progreso > 0 else { return }
                var arco = Path()
                arco.addArc(
                    center: centro,
                    radius: radio,
                    startAngle: .degrees(-90),
                    endAngle: .degrees(-90 + 360 * progreso),
                    clockwise: false
                )
                context.stroke(
                    arco,
                    with: .color(hayAlgoPendiente ? Color(nsColor: .systemOrange) : .primary),
                    style: StrokeStyle(lineWidth: grosor, lineCap: .round)
                )
            }
            Image(systemName: "target")
                .font(.system(size: 6, weight: .bold))
        }
        .frame(width: 16, height: 16)
        .help(ayuda)
    }

    /// Qué parte del día está cerrada (0…1). Sin datos todavía, 0.
    private var progreso: Double {
        guard model.isSignedIn, let day = model.dayClose else { return 0 }
        let hechas = day.completed.count
        let abiertas = day.openTasks + day.pendingCaptures
        let total = hechas + abiertas
        guard total > 0 else { return 1 }
        return Double(hechas) / Double(total)
    }

    // MARK: - Cifra

    /// Capturas esperando (según el servidor) más las que no han podido salir.
    private var pending: Int? {
        guard model.isSignedIn, let day = model.dayClose else { return nil }
        return day.pendingCaptures + model.queued.count
    }

    private var hayAlgoPendiente: Bool {
        (pending ?? 0) > 0
    }

    private var ayuda: String {
        guard model.isSignedIn, let day = model.dayClose else {
            return "LifeOS"
        }
        let cerradas = day.completed.count
        let abiertas = day.openTasks + day.pendingCaptures
        var texto = "\(cerradas) cerradas, \(abiertas) por hacer"
        if let pending, pending > 0 {
            texto += " · \(pending) captura\(pending == 1 ? "" : "s") esperando"
        }
        if !model.queued.isEmpty {
            texto += " · \(model.queued.count) sin enviar"
        }
        return texto
    }
}
