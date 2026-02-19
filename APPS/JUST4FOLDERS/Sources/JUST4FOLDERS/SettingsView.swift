import SwiftUI

struct SettingsView: View {
    @AppStorage(J4FPreferences.Keys.deleteBehavior) private var deleteBehaviorRaw = DeleteBehaviorPreference.trashIfPossible.rawValue
    @AppStorage(J4FPreferences.Keys.showHiddenFiles) private var showHiddenFiles = false
    @AppStorage(J4FPreferences.Keys.preferredBigBufferMB) private var preferredBigBufferMB = 4

    private var deleteBehaviorBinding: Binding<DeleteBehaviorPreference> {
        Binding(
            get: { DeleteBehaviorPreference(rawValue: deleteBehaviorRaw) ?? .trashIfPossible },
            set: { deleteBehaviorRaw = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Picker("Comportamiento de borrar", selection: deleteBehaviorBinding) {
                ForEach(DeleteBehaviorPreference.allCases) { option in
                    Text(option.title).tag(option)
                }
            }

            Toggle("Mostrar archivos ocultos", isOn: $showHiddenFiles)

            Stepper(value: $preferredBigBufferMB, in: 1...8) {
                Text("Buffer Big inicial: \(preferredBigBufferMB) MB")
            }
        }
        .padding(16)
        .frame(width: 460)
        .onAppear {
            preferredBigBufferMB = max(1, min(8, preferredBigBufferMB))
            postChanged()
        }
        .onChange(of: deleteBehaviorRaw) { _, _ in postChanged() }
        .onChange(of: showHiddenFiles) { _, _ in postChanged() }
        .onChange(of: preferredBigBufferMB) { _, newValue in
            preferredBigBufferMB = max(1, min(8, newValue))
            postChanged()
        }
    }

    private func postChanged() {
        NotificationCenter.default.post(name: .j4fPreferencesChanged, object: nil)
    }
}
