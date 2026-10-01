import LifeOSAPI
import LifeOSCore
import SwiftUI

/// Grabar una nota de voz y enviarla.
///
/// El audio se sube y **lo transcribe el servidor** (transcribir en el Mac no daba
/// la latencia). Y si la nota va marcada como sensible, el servidor guarda el
/// audio y **no** lo transcribe: eso se dice antes y después, no se deja a medias.
struct VoiceControls: View {
    @ObservedObject var model: LifeOSModel

    var body: some View {
        HStack(spacing: LifeOSSpace.s) {
            if model.recorder.isRecording {
                recording
            } else {
                Button {
                    Task { await model.startRecording() }
                } label: {
                    Label("Grabar", systemImage: "mic")
                }
                .buttonStyle(LifeOSGhostButtonStyle())
                .disabled(model.isSendingAudio || model.busy)
                .help("Grabar una nota de voz (la transcribe LifeOS)")
            }

            if model.isSendingAudio {
                HStack(spacing: LifeOSSpace.xs) {
                    ProgressView().controlSize(.small)
                    Text("Enviando la nota…")
                        .font(LifeOSFont.caption)
                        .foregroundStyle(LifeOSTheme.textTertiary)
                }
            }
        }
    }

    private var recording: some View {
        HStack(spacing: LifeOSSpace.s) {
            HStack(spacing: LifeOSSpace.xs) {
                Circle()
                    .fill(LifeOSTheme.danger)
                    .frame(width: 8, height: 8)
                Text(model.recorder.elapsedLabel)
                    .font(LifeOSFont.mono)
                    .foregroundStyle(LifeOSTheme.textPrimary)
            }
            .padding(.horizontal, LifeOSSpace.m)
            .padding(.vertical, 5)
            .background(Capsule().fill(LifeOSTheme.dangerSoft))

            Button("Enviar") { Task { await model.sendRecording() } }
                .buttonStyle(LifeOSPrimaryButtonStyle())
                .disabled(model.isSendingAudio)

            Button("Descartar") { model.cancelRecording() }
                .buttonStyle(LifeOSGhostButtonStyle())
        }
    }
}
