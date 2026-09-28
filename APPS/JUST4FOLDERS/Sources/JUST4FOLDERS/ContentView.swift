import SwiftUI

struct ContentView: View {
    var body: some View {
        // v2.1 — OJO: con solo minWidth/minHeight, el NSViewControllerRepresentable se queda
        // en su tamaño «fitting» (~965pt) y NO llena la ventana al redimensionar/restaurar;
        // maxWidth/maxHeight .infinity lo estiran a la ventana completa.
        CommanderContainerView()
            .frame(minWidth: 980, maxWidth: .infinity, minHeight: 620, maxHeight: .infinity)
    }
}

private struct CommanderContainerView: NSViewControllerRepresentable {
    func makeNSViewController(context: Context) -> CommanderViewController {
        CommanderViewController()
    }

    func updateNSViewController(_ nsViewController: CommanderViewController, context: Context) {
        // No-op in MVP-1; controller is stateful and self-managed.
    }

    // v2.1.1 — sin esto, el hosting usa el tamaño «fitting» del NSView y el contenido vuelve a
    // quedar centrado sin llenar la ventana (pasaba con restricciones internas del split).
    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsViewController: CommanderViewController,
        context: Context
    ) -> CGSize? {
        CGSize(width: proposal.width ?? 1320, height: proposal.height ?? 860)
    }
}
