import AppKit

/// v2.3.7 — Puente a **JUST4PICT** para el menú contextual (y futuro uso del Panel Hub).
///
/// Usa el CLI `just4pict-cli` (vive dentro del binario de JUST4PICT: mismo pipeline PRO sin UI)
/// y ejecuta las mejoras **en background**, sin bloquear la UI. Nunca sobrescribe: el CLI crea
/// ficheros NUEVOS con sufijo (`base-enhanced-<stamp>.ext`) junto al original.
enum Just4PictActions {

    struct OperationResult {
        let success: Bool
        let message: String
        /// Ficheros creados (para refrescar el panel al terminar).
        let created: [URL]
    }

    // MARK: - Detección del CLI

    private static var cachedCLI: URL?

    /// CLI disponible, en orden: `just4pict-cli` del PATH → script del repo → binarios de SwiftPM
    /// del repo (solo si SOPORTAN el CLI: un build anterior arrancaría la GUI y colgaría el
    /// comando) → app instalada (también verificada). El negativo NO se cachea (permite compilar
    /// JUST4PICT después y que el menú lo detecte sin reiniciar FOLDERS).
    static func cliURL() -> URL? {
        if let cachedCLI { return cachedCLI }
        guard let resolved = resolveCLI() else { return nil }
        cachedCLI = resolved
        return resolved
    }

    static var isAvailable: Bool { cliURL() != nil }

    private static func resolveCLI() -> URL? {
        let fileManager = FileManager.default

        // 1) En el PATH del usuario.
        for directory in (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent("just4pict-cli")
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        guard let root = repositoryRoot() else { return nil }
        let pictRoot = root.appendingPathComponent("APPS/JUST4PICT")

        // 2) Script del repo (se auto-valida internamente).
        let script = pictRoot.appendingPathComponent("scripts/just4pict-cli")
        if fileManager.isExecutableFile(atPath: script.path) {
            return script
        }

        // 3) Binarios de SwiftPM, solo si el binario lleva el CLI incrustado.
        for relative in [".build/debug/JUST4PICT", ".build/release/JUST4PICT"] {
            let binary = pictRoot.appendingPathComponent(relative)
            if fileManager.isExecutableFile(atPath: binary.path), supportsCLI(binary) {
                return binary
            }
        }

        // 4) App instalada (LaunchServices), verificada igual que los binarios.
        if let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.dmx83.just4pict"),
           let executable = Bundle(url: installed)?.executableURL,
           supportsCLI(executable) {
            return executable
        }

        return nil
    }

    /// ¿El binario soporta el CLI? (marca incrustada en el propio ejecutable; los builds
    /// anteriores al CLI no la tienen y arrancarían la app con UI).
    private static func supportsCLI(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return false }
        return data.range(of: Data("just4pict-cli".utf8)) != nil
    }

    /// Raíz del repo de desarrollo (busca `PACKAGES/J4SHARED` + `APPS/JUST4PICT` hacia arriba).
    private static func repositoryRoot() -> URL? {
        var directory = Bundle.main.executableURL?.resolvingSymlinksInPath().deletingLastPathComponent()
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<8 {
            let marker = directory.appendingPathComponent("PACKAGES/J4SHARED")
            let pict = directory.appendingPathComponent("APPS/JUST4PICT")
            if FileManager.default.fileExists(atPath: marker.path),
               FileManager.default.fileExists(atPath: pict.path) {
                return directory
            }
            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path { break }
            directory = parent
        }
        return nil
    }

    // MARK: - Operaciones (background + completion en main)

    /// Presets aceptados por el CLI, con su nombre para la UI.
    static let presets: [(id: String, name: String)] = [
        ("auto", "Automático"),
        ("retrato", "Retrato"),
        ("paisaje", "Paisaje"),
        ("documento", "Documento"),
        ("ecommerce", "Ecommerce")
    ]

    /// Mejora las imágenes con el pipeline PRO de JUST4PICT (sin IA) creando ficheros NUEVOS.
    static func enhance(_ images: [URL], preset: String, completion: @escaping (OperationResult) -> Void) {
        guard !images.isEmpty else {
            completion(OperationResult(success: false, message: "JUST4PICT: no hay imágenes que mejorar.", created: []))
            return
        }
        guard let cli = cliURL() else {
            completion(OperationResult(
                success: false,
                message: "JUST4PICT: CLI no disponible (compila APPS/JUST4PICT con «swift build» o instala la app).",
                created: []
            ))
            return
        }

        let presetName = presets.first(where: { $0.id == preset })?.name ?? preset
        background {
            var arguments = ["enhance", "-p", preset, "--json"]
            arguments.append(contentsOf: images.map(\.path))
            let outcome = run(cli, arguments)
            let summary = parseJSONSummary(outcome.output)

            if let summary, !summary.created.isEmpty {
                let note = summary.failed > 0 ? " · \(summary.failed) fallo(s)" : ""
                return OperationResult(
                    success: true,
                    message: "JUST4PICT: \(summary.created.count) imagen(es) mejoradas (preset \(presetName))\(note). Ficheros nuevos.",
                    created: summary.created.map { URL(fileURLWithPath: $0) }
                )
            }

            // Sin JSON usable: si el proceso falló, mostramos la primera línea de detalle.
            let detail = firstLine(of: outcome.output.isEmpty ? "sin salida" : outcome.output)
            return OperationResult(
                success: false,
                message: "JUST4PICT: no se pudo mejorar (\(detail)).",
                created: []
            )
        } completion: { completion($0) }
    }

    // MARK: - Utilidades

    private struct JSONSummary {
        let created: [String]
        let failed: Int
    }

    /// Extrae `{"created":[…],"failed":N}` del stdout mezclado con el progreso de stderr.
    private static func parseJSONSummary(_ output: String) -> JSONSummary? {
        guard let line = output.split(separator: "\n").first(where: {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("{")
        }) else {
            return nil
        }
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let created = object["created"] as? [String] else {
            return nil
        }
        return JSONSummary(created: created, failed: object["failed"] as? Int ?? 0)
    }

    private static func firstLine(of output: String) -> String {
        output.split(separator: "\n").first.map(String.init) ?? "sin detalle"
    }

    private static let queue = DispatchQueue(label: "com.dmx83.just4folders.just4pict", qos: .userInitiated)

    private static func background(_ work: @escaping () -> OperationResult, completion: @escaping (OperationResult) -> Void) {
        queue.async {
            let result = work()
            DispatchQueue.main.async { completion(result) }
        }
    }

    @discardableResult
    private static func run(_ executable: URL, _ arguments: [String]) -> (code: Int32, output: String) {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (-1, error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
