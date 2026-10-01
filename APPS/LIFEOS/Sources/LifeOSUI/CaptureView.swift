import LifeOSAPI
import LifeOSCore
import SwiftUI

/// Capturar es la acción más importante de la app: se escribe, LifeOS propone y
/// la persona confirma. Nada se guarda sin confirmación.
public struct CaptureView: View {
    @ObservedObject private var model: LifeOSModel
    private let focusOnAppear: Bool

    @FocusState private var editorFocused: Bool

    public init(model: LifeOSModel, focusOnAppear: Bool = false) {
        self.model = model
        self.focusOnAppear = focusOnAppear
    }

    public var body: some View {
        ScrollView {
            CaptureContent(model: model, focusOnAppear: focusOnAppear)
        }
    }
}

/// El contenido de «Capturar», sin el contenedor con scroll.
struct CaptureContent: View {
    @ObservedObject var model: LifeOSModel
    var focusOnAppear: Bool = false

    @FocusState private var editorFocused: Bool
    @Environment(\.lifeOSFlatSurfaces) private var renderMode

    var body: some View {
        VStack(alignment: .leading, spacing: LifeOSSpace.l) {
            header
            composer
            stateSection
            messages
        }
        .padding(.horizontal, LifeOSSpace.xl)
        .padding(.vertical, LifeOSSpace.xl)
        .frame(maxWidth: 760, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(LifeOSTheme.canvas)
    }

    // MARK: - Cabecera

    private var header: some View {
        LifeOSScreenHeader(
            eyebrow: "Capturar",
            title: "¿Qué tienes en la cabeza?",
            detail: "Escribe como hablas y LifeOS propone el tipo. Tú confirmas: nada se guarda solo."
        ) {
            EmptyView()
        }
    }

    // MARK: - Compositor

    private var composer: some View {
        LifeOSCard {
            VStack(alignment: .leading, spacing: LifeOSSpace.m) {
                editor
                footer
            }
        }
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if model.draft.isEmpty {
                Text("Llamar al dentista mañana · idea para la web · pesé 78,5")
                    .font(LifeOSFont.bodyLarge)
                    .foregroundStyle(LifeOSTheme.textTertiary)
                    .padding(.horizontal, LifeOSSpace.s)
                    .padding(.vertical, LifeOSSpace.s)
                    .allowsHitTesting(false)
            }
            if renderMode {
                // Fuera de pantalla, AppKit no pinta el editor de texto.
                Text(model.draft)
                    .font(LifeOSFont.bodyLarge)
                    .foregroundStyle(LifeOSTheme.textPrimary)
                    .padding(LifeOSSpace.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextEditor(text: $model.draft)
                    .font(LifeOSFont.bodyLarge)
                    .foregroundStyle(LifeOSTheme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 104)
                    .padding(LifeOSSpace.xs)
                    .focused($editorFocused)
            }
        }
        .frame(minHeight: 96, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: LifeOSRadius.lg, style: .continuous)
                .fill(LifeOSTheme.elevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LifeOSRadius.lg, style: .continuous)
                .strokeBorder(
                    editorFocused && !renderMode ? LifeOSTheme.focusRing : Color.clear,
                    lineWidth: 2
                )
        )
        .animation(LifeOSMotion.standard, value: editorFocused)
        .onAppear {
            guard focusOnAppear, !renderMode else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { editorFocused = true }
        }
    }

    private var footer: some View {
        HStack(spacing: LifeOSSpace.s) {
            SensitiveToggle(isOn: $model.draftSensitive)
            VoiceControls(model: model)

            Spacer(minLength: 0)

            if case .working = model.draftState {
                ProgressView().controlSize(.small)
            }

            Text("⌘↩")
                .font(LifeOSFont.caption)
                .foregroundStyle(LifeOSTheme.textTertiary)

            Button("Anotar") { Task { await model.sendDraft() } }
                .buttonStyle(LifeOSPrimaryButtonStyle())
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(canSend == false)
        }
    }

    private var canSend: Bool {
        !model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !model.busy
    }
    // MARK: - Estado

    @ViewBuilder
    private var stateSection: some View {
        switch model.draftState {
        case .idle:
            EmptyView()
        case .working(let message):
            WorkingRow(text: message)
        case .proposal(let proposal):
            ProposalReview(
                proposal: proposal,
                selection: model.selectedOperations,
                onToggle: { model.toggleOperation($0) },
                onApply: { Task { await model.applySelected() } },
                onReject: { Task { await model.rejectDraft() } }
            )
        case .clarification(_, let question):
            ClarificationCard(question: question) { answer, kind in
                Task { await model.answerClarification(answer, manualKind: kind) }
            }
        case .queued(let item):
            QueuedCard(item: item) {
                Task {
                    await model.flushOutbox()
                    model.dismissQueuedNotice()
                }
            }
        }
    }

    @ViewBuilder
    private var messages: some View {
        if let error = model.errorMessage {
            MessageRow(text: error, tone: .danger, systemImage: "exclamationmark.triangle.fill")
        }
    }
}

/// Interruptor de sensibilidad, con su explicación a mano.
struct SensitiveToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: LifeOSSpace.xs) {
                Image(systemName: isOn ? "lock.fill" : "lock.open")
                    .font(.system(size: 10, weight: .bold))
                Text("Sensible")
                    .font(LifeOSFont.labelSmall)
            }
            .foregroundStyle(isOn ? LifeOSTheme.warning : LifeOSTheme.textSecondary)
            .padding(.horizontal, LifeOSSpace.m)
            .padding(.vertical, 6)
            .background(Capsule().fill(isOn ? LifeOSTheme.warningSoft : LifeOSTheme.elevated))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(LifeOSMotion.standard, value: isOn)
        .help("Lo sensible no se manda a proveedores de IA externos ni se indexa.")
    }
}
