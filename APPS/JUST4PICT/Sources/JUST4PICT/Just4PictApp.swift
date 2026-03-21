import SwiftUI
import AppKit

@main
struct Just4PictApp: App {
    private let launchSessionID = UUID()

    var body: some Scene {
        WindowGroup("JUST4PICT \(BuildInfo.displayLabel)") {
            ContentView(
                initialFormat: .preferredDefault,
                initialQuality: OutputFormat.preferredQualityDefault
            )
                .id(launchSessionID)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    DispatchQueue.main.async {
                        guard let window = NSApplication.shared.windows.first else { return }
                        window.title = "JUST4PICT \(BuildInfo.displayLabel)"
                        window.makeKeyAndOrderFront(nil)
                    }
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
    }
}
