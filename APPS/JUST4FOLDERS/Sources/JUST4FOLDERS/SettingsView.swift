import SwiftUI
import J4FUI

struct SettingsView: View {
    @AppStorage(J4FPreferences.Keys.deleteBehavior) private var deleteBehaviorRaw = DeleteBehaviorPreference.trashIfPossible.rawValue
    @AppStorage(J4FPreferences.Keys.showHiddenFiles) private var showHiddenFiles = false
    @AppStorage(J4FPreferences.Keys.preferredBigBufferMB) private var preferredBigBufferMB = 4
    @AppStorage(J4FPreferences.Keys.visualStyle) private var visualStyleRaw = J4FVisualStyle.esmeralda.rawValue

    private var selectedStyle: J4FVisualStyle {
        J4FVisualStyle(rawValue: visualStyleRaw) ?? .esmeralda
    }

    private var deleteBehaviorBinding: Binding<DeleteBehaviorPreference> {
        Binding(
            get: { DeleteBehaviorPreference(rawValue: deleteBehaviorRaw) ?? .trashIfPossible },
            set: { deleteBehaviorRaw = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section("Apariencia") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(J4FVisualStyle.allCases) { style in
                        Button {
                            visualStyleRaw = style.rawValue
                        } label: {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color(nsColor: style.brand))
                                    .frame(width: 14, height: 14)
                                    .overlay(Circle().strokeBorder(Color(nsColor: .separatorColor)))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(style.title)
                                    Text(style.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                if selectedStyle == style {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }

            Section("General") {
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
        }
        .padding(16)
        .frame(width: 460)
        .onAppear {
            preferredBigBufferMB = max(1, min(8, preferredBigBufferMB))
            postChanged()
        }
        .onChange(of: visualStyleRaw) { _, _ in postChanged() }
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
