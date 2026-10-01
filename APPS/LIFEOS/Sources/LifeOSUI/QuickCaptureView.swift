import LifeOSAPI
import LifeOSCore
import SwiftUI

/// Captura rápida del panel flotante (⌥Espacio).
///
/// Misma secuencia que `CaptureView` (escribir → propuesta → confirmar), en un
/// panel acotado que no crece sin control.
public struct QuickCaptureView: View {
    @ObservedObject private var model: LifeOSModel
    private let onClose: () -> Void

    @FocusState private var focused: Bool
    @Environment(\.lifeOSFlatSurfaces) private var flatSurfaces
    @Environment(\.lifeOSFlatSurfaces) private var renderMode

    public init(model: LifeOSModel, onClose: @escaping () -> Void) {
        self.model = model
        self.onClose = onClose
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: LifeOSSpace.m) {
            header
            editor
            footer
            stateArea
        }
        .padding(LifeOSSpace.l)
        .frame(width: 580)
        .background(
            RoundedRectangle(cornerRadius: LifeOSRadius.panel, style: .continuous)
                .fill(flatSurfaces ? AnyShapeStyle(LifeOSTheme.surface) : AnyShapeStyle(.regularMaterial))
        )
        .overlay(
            RoundedRectangle(cornerRadius: LifeOSRadius.panel, style: .continuous)
                .strokeBorder(LifeOSTheme.borderSubtle, lineWidth: 1)
        )
        .onExitCommand(perform: onClose)
        .onAppear { focused = true }
    }

    private var header: some View {
        HStack(spacing: LifeOSSpace.s) {
            BrandMark(size: 22)
            Text("Capturar en LifeOS")
                .font(LifeOSFont.label)
                .foregroundStyle(LifeOSTheme.textPrimary)
            Spacer(minLength: 0)
            Text("⌘↩ anotar · Esc cerrar")
                .font(LifeOSFont.caption)
                .foregroundStyle(LifeOSTheme.textTertiary)
        }
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if model.draft.isEmpty {
                Text("Escribe y pulsa ⌘↩…")
                    .font(LifeOSFont.bodyLarge)
                    .foregroundStyle(LifeOSTheme.textTertiary)
                    .padding(.horizontal, LifeOSSpace.s)
                    .padding(.vertical, LifeOSSpace.s)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $model.draft)
                .font(LifeOSFont.bodyLarge)
                .foregroundStyle(LifeOSTheme.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(height: 84)
                .padding(LifeOSSpace.xs)
                .focused($focused)
                .opacity(renderMode ? 0 : 1)
        }
        .frame(height: 104, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: LifeOSRadius.lg, style: .continuous)
                .fill(LifeOSTheme.elevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LifeOSRadius.lg, style: .continuous)
                .strokeBorder(
                    focused && !renderMode ? LifeOSTheme.focusRing : Color.clear,
                    lineWidth: 2
                )
        )
        .animation(LifeOSMotion.standard, value: focused)
    }

    private var footer: some View {
        HStack(spacing: LifeOSSpace.s) {
            SensitiveToggle(isOn: $model.draftSensitive)
            Spacer(minLength: 0)
            if case .working = model.draftState {
                ProgressView().controlSize(.small)
            }
            Button("Anotar") { Task { await model.sendDraft() } }
                .buttonStyle(LifeOSPrimaryButtonStyle())
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.busy)
        }
    }

    @ViewBuilder
    private var stateArea: some View {
        switch model.draftState {
        case .idle:
            EmptyView()
        case .working(let message):
            WorkingRow(text: message)
        case .proposal(let proposal):
            ScrollView {
                ProposalReview(
                    proposal: proposal,
                    selection: model.selectedOperations,
                    onToggle: { model.toggleOperation($0) },
                    onApply: { Task { await model.applySelected() } },
                    onReject: { Task { await model.rejectDraft() } }
                )
            }
            .frame(maxHeight: 260)
        case .clarification(_, let question):
            ScrollView {
                ClarificationCard(question: question) { answer, kind in
                    Task { await model.answerClarification(answer, manualKind: kind) }
                }
            }
            .frame(maxHeight: 260)
        case .queued(let item):
            QueuedCard(item: item) {
                Task {
                    await model.flushOutbox()
                    model.dismissQueuedNotice()
                }
            }
        }

        if let error = model.errorMessage {
            MessageRow(text: error, tone: .danger, systemImage: "exclamationmark.triangle.fill")
        }
    }
}
