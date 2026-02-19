import SwiftUI

struct ContentView: View {
    var body: some View {
        CommanderContainerView()
            .frame(minWidth: 980, minHeight: 620)
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
