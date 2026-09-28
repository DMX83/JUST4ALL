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
}
