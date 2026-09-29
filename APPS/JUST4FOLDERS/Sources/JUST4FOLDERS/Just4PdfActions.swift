import AppKit

/// v2.3.5 — Puente a **JUST4PDF** para el menú contextual y el Panel Hub.
///
/// Localiza el CLI `just4pdf-cli` (en el PATH del usuario o en el venv del repo, con fallback
/// `python -m just4pdf.cli`) y ejecuta las operaciones **en background**, sin bloquear la UI.
/// Usa los mismos servicios que la app JUST4PDF (una sola fuente de verdad del motor PDF) y
/// **nunca sobrescribe**: cada salida recibe un nombre único junto al origen.
enum Just4PdfActions {

    struct OperationResult {
        let success: Bool
        let message: String
        /// Ficheros/carpetas nuevos (para seleccionar/refrescar al terminar).
        let created: [URL]
    }

    // MARK: - Detección

    private struct Bridge {
        let executable: URL
        let prefixArguments: [String]
    }

    private static var cachedBridge: Bridge??

    /// CLI disponible: PATH del usuario → venv del repo (junto al repositorio de desarrollo) →
    /// venv con `python -m just4pdf.cli`.
    static func bridge() -> (executable: URL, prefixArguments: [String])? {
        if let cached = cachedBridge {
            return cached.map { ($0.executable, $0.prefixArguments) }
        }
        let resolved = resolveBridge()
        cachedBridge = .some(resolved)
        return resolved.map { ($0.executable, $0.prefixArguments) }
    }

    static var isAvailable: Bool { bridge() != nil }

    private static func resolveBridge() -> Bridge? {
        // 1) just4pdf-cli en el PATH.
        let pathDirectories = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
        for directory in pathDirectories {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent("just4pdf-cli")
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return Bridge(executable: candidate, prefixArguments: [])
            }
        }
        // 2) Venv del repositorio (desarrollo): se busca hacia arriba desde el binario.
        if let root = repositoryRoot() {
            let cli = root.appendingPathComponent(".venv/bin/just4pdf-cli")
            if FileManager.default.isExecutableFile(atPath: cli.path) {
                return Bridge(executable: cli, prefixArguments: [])
            }
            // 3) Fallback: python del venv + módulo.
            let python = root.appendingPathComponent(".venv/bin/python")
            if FileManager.default.isExecutableFile(atPath: python.path) {
                let probe = run(python, ["-c", "import just4pdf.cli"])
                if probe.code == 0 {
                    return Bridge(executable: python, prefixArguments: ["-m", "just4pdf.cli"])
                }
            }
        }
        return nil
    }

    /// Raíz del repo de desarrollo (busca `.venv` + `PACKAGES/J4SHARED` hacia arriba).
    private static func repositoryRoot() -> URL? {
        var directory = Bundle.main.executableURL?.resolvingSymlinksInPath().deletingLastPathComponent()
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<8 {
            let venv = directory.appendingPathComponent(".venv")
            let marker = directory.appendingPathComponent("PACKAGES/J4SHARED")
            if FileManager.default.fileExists(atPath: venv.path),
               FileManager.default.fileExists(atPath: marker.path) {
                return directory
            }
            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path { break }
            directory = parent
        }
        return nil
    }

    /// App JUST4PDF (para «Abrir con»): registro de LaunchServices → build local del repo.
    static func appURL() -> URL? {
        if let registered = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.dmx83.just4pdf") {
            return registered
        }
        if let root = repositoryRoot() {
            let local = root.appendingPathComponent("APPS/JUST4PDF/build/Build/Products/Release/JUST4PDF.app")
            if FileManager.default.fileExists(atPath: local.path) {
                return local
            }
        }
        return nil
    }

    // MARK: - Operaciones (background + completion en main)

    static func merge(_ pdfs: [URL], completion: @escaping (OperationResult) -> Void) {
        guard pdfs.count >= 2, let bridge = resolveBridge() else {
            completion(OperationResult(success: false, message: "JUST4PDF no está disponible para unir.", created: []))
            return
        }
        let output = uniqueURL(in: pdfs[0].deletingLastPathComponent(), base: "unido", ext: "pdf")
        background {
            let result = run(bridge.executable, bridge.prefixArguments + ["merge", "-o", output.path] + pdfs.map(\.path))
            if result.code == 0 {
                return OperationResult(
                    success: true,
                    message: "JUST4PDF: unidos \(pdfs.count) PDFs → \(output.lastPathComponent).",
                    created: [output]
                )
            }
            return OperationResult(
                success: false,
                message: "JUST4PDF: no se pudo unir (\(firstLine(of: result.output))).",
                created: []
            )
        } completion: { completion($0) }
    }

    static func compressAll(_ pdfs: [URL], level: String, completion: @escaping (OperationResult) -> Void) {
        guard !pdfs.isEmpty, let bridge = resolveBridge() else {
            completion(OperationResult(success: false, message: "JUST4PDF no está disponible para comprimir.", created: []))
            return
        }
        let levelName = level == "low" ? "bajo" : (level == "high" ? "alto" : "medio")
        background {
            var created: [URL] = []
            var skipped = 0
            var failures = 0
            var totalBefore: Int64 = 0
            var totalAfter: Int64 = 0
            for pdf in pdfs {
                let base = pdf.deletingPathExtension().lastPathComponent
                let output = uniqueURL(in: pdf.deletingLastPathComponent(), base: base + "-comprimido", ext: "pdf")
                let result = run(bridge.executable, bridge.prefixArguments + ["compress", "--level", level, "-o", output.path, pdf.path])
                if result.code != 0 {
                    failures += 1
                    continue
                }
                let parts = result.output.split(separator: "\t")
                if parts.count >= 3, let before = Int64(parts[1]), let after = Int64(parts[2]), FileManager.default.fileExists(atPath: output.path) {
                    created.append(output)
                    totalBefore += before
                    totalAfter += after
                } else {
                    skipped += 1 // sin-ganancia: el servicio no conservó la salida
                }
            }
            if failures > 0 && created.isEmpty {
                return OperationResult(success: false, message: "JUST4PDF: fallo al comprimir (\(failures)).", created: [])
            }
            var message = "JUST4PDF: comprimido(s) \(created.count) PDF(s) (nivel \(levelName))"
            if totalBefore > 0 {
                let saved = max(0, totalBefore - totalAfter)
                message += ", \(saved / 1024) KB menos"
            }
            if skipped > 0 {
                message += " · \(skipped) sin ganancia (se queda el original)"
            }
            if failures > 0 {
                message += " · \(failures) fallo(s)"
            }
            return OperationResult(success: !created.isEmpty, message: message + ".", created: created)
        } completion: { completion($0) }
    }

    static func pdfToImages(_ pdf: URL, completion: @escaping (OperationResult) -> Void) {
        guard let bridge = resolveBridge() else {
            completion(OperationResult(success: false, message: "JUST4PDF no está disponible para exportar.", created: []))
            return
        }
        let base = pdf.deletingPathExtension().lastPathComponent
        let directory = uniqueURL(in: pdf.deletingLastPathComponent(), base: base + " Paginas", ext: nil)
        background {
            let result = run(bridge.executable, bridge.prefixArguments + ["pdf2img", "--zoom", "2.0", "--out-dir", directory.path, pdf.path])
            if result.code == 0 {
                let pages = result.output.split(separator: "\n").count
                return OperationResult(
                    success: true,
                    message: "JUST4PDF: \(pages) página(s) exportadas a «\(directory.lastPathComponent)».",
                    created: [directory]
                )
            }
            return OperationResult(
                success: false,
                message: "JUST4PDF: no se pudo exportar (\(firstLine(of: result.output))).",
                created: []
            )
        } completion: { completion($0) }
    }

    static func imagesToPDF(_ images: [URL], completion: @escaping (OperationResult) -> Void) {
        guard images.count >= 2, let bridge = resolveBridge() else {
            completion(OperationResult(success: false, message: "JUST4PDF no está disponible para crear el PDF.", created: []))
            return
        }
        let folderName = images[0].deletingLastPathComponent().lastPathComponent
        let base = folderName.isEmpty ? "imagenes" : folderName
        let output = uniqueURL(in: images[0].deletingLastPathComponent(), base: base, ext: "pdf")
        background {
            let result = run(bridge.executable, bridge.prefixArguments + ["img2pdf", "-o", output.path] + images.map(\.path))
            if result.code == 0 {
                return OperationResult(
                    success: true,
                    message: "JUST4PDF: creado \(output.lastPathComponent) con \(images.count) imagen(es).",
                    created: [output]
                )
            }
            return OperationResult(
                success: false,
                message: "JUST4PDF: no se pudo crear el PDF (\(firstLine(of: result.output))).",
                created: []
            )
        } completion: { completion($0) }
    }

    /// «Abrir con JUST4PDF» (la app maneja argv y FileOpen; ver app.py).
    static func openWith(_ pdfs: [URL], completion: @escaping (String) -> Void) {
        guard let app = appURL() else {
            completion("JUST4PDF no está instalado (no se encontró la app).")
            NSSound.beep()
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open(pdfs, withApplicationAt: app, configuration: configuration) { _, error in
            if let error {
                completion("No se pudo abrir JUST4PDF: \(error.localizedDescription)")
            } else {
                completion("Abierto en JUST4PDF (\(pdfs.count) PDF(s)).")
            }
        }
    }

    // MARK: - Utilidades

    private static let queue = DispatchQueue(label: "com.dmx83.just4folders.just4pdf", qos: .userInitiated)

    private static func background(_ work: @escaping () -> OperationResult, completion: @escaping (OperationResult) -> Void) {
        queue.async {
            let result = work()
            DispatchQueue.main.async { completion(result) }
        }
    }

    private static func uniqueURL(in directory: URL, base: String, ext: String?) -> URL {
        func candidate(_ name: String) -> URL {
            guard let ext, !ext.isEmpty else { return directory.appendingPathComponent(name) }
            return directory.appendingPathComponent("\(name).\(ext)")
        }
        var url = candidate(base)
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = candidate("\(base) \(counter)")
            counter += 1
        }
        return url
    }

    private static func firstLine(of output: String) -> String {
        output.split(separator: "\n").first.map(String.init) ?? "sin detalle"
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
