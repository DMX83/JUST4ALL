import AVFoundation
import Foundation

/// Grabar la voz en el Mac, para enviarla a LifeOS y que la transcriba allí.
///
/// Se graba en **m4a mono a 16 kHz**, que es lo que aceptan los transcriptores y
/// ocupa poco: una nota de un minuto son unos 120 KB, muy lejos del límite de
/// 25 MB del servidor.
///
/// El fichero va a una carpeta temporal y **se borra siempre** (al enviarlo, al
/// cancelar y al cerrar la app): el audio solo vive aquí mientras se decide qué
/// hacer con él. Lo que se guarda es el audio en LifeOS, no una copia local.
@MainActor
public final class VoiceRecorder: ObservableObject {
    @Published public private(set) var isRecording = false
    @Published public private(set) var seconds = 0
    @Published public private(set) var errorMessage: String?

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var fileURL: URL?
    private var startedAt: Date?

    /// El límite del servidor son 25 MB; con este formato son horas, pero se
    /// corta a los 15 minutos para no dejar grabando sin querer.
    public static let maximumSeconds = 15 * 60

    public init() {}

    /// Pide permiso al sistema. Hace falta que la app esté **empaquetada** (el
    /// permiso se pide con el `Info.plist` del bundle).
    public static func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    public func start() async {
        guard !isRecording else { return }
        errorMessage = nil

        guard await Self.requestPermission() else {
            errorMessage = "macOS no ha dado permiso para el micrófono. Se concede en Ajustes del Sistema → Privacidad y seguridad → Micrófono."
            return
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lifeos-voz-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = false
            guard recorder.record() else {
                errorMessage = "No se pudo empezar a grabar."
                return
            }
            self.recorder = recorder
            self.fileURL = url
            self.startedAt = Date()
            self.seconds = 0
            self.isRecording = true
            startTimer()
        } catch {
            errorMessage = "No se pudo empezar a grabar: \(error.localizedDescription)"
        }
    }

    /// Termina y devuelve lo grabado, listo para subir. `nil` si no había nada.
    public func stop() -> (data: Data, filename: String)? {
        guard let recorder, let fileURL else { return nil }
        recorder.stop()
        stopTimer()
        isRecording = false
        self.recorder = nil
        self.fileURL = nil
        seconds = 0
        startedAt = nil

        defer { try? FileManager.default.removeItem(at: fileURL) }
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else {
            errorMessage = "La grabación salió vacía."
            return nil
        }
        return (data, fileURL.lastPathComponent)
    }

    /// Tira lo grabado y limpia.
    public func cancel() {
        recorder?.stop()
        stopTimer()
        isRecording = false
        recorder = nil
        seconds = 0
        startedAt = nil
        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
            self.fileURL = nil
        }
    }

    public var elapsedLabel: String {
        let minutes = seconds / 60
        let remainder = seconds % 60
        return String(format: "%d:%02d", minutes, remainder)
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.seconds += 1
                if self.seconds >= Self.maximumSeconds {
                    self.errorMessage = "Se ha parado a los 15 minutos: envía la nota y graba otra si hace falta."
                    _ = self.stop()
                }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
