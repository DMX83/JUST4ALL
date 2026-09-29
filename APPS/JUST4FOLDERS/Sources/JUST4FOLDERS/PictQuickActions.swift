import AppKit

/// v2.3.3 — Acciones rápidas de imagen **compartidas** entre el módulo PICT (Panel Hub) y el
/// menú contextual de los paneles (submenú «JUST4PICT»).
///
/// Usa `sips` (nativo de macOS) y **nunca sobrescribe**: cada acción crea un fichero NUEVO junto
/// al original (sufijos `-png`, `-jpg`, `-50%`, y « 2», « 3»… si ya existe). Las conversiones no
/// dependen de que JUST4PICT esté instalada; cuando su roadmap sume CLI/documentos, aquí se
/// enchufarán las acciones «de app» (editar/mejorar con JUST4PICT).
enum PictQuickActions {

    static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "tiff", "tif", "webp", "gif", "bmp"
    ]

    struct Result {
        let created: [URL]
        let failures: Int
    }

    static func isImage(_ url: URL) -> Bool {
        imageExtensions.contains(url.pathExtension.lowercased())
    }

    static func images(in urls: [URL]) -> [URL] {
        urls.filter { isImage($0) }
    }

    /// Convierte a `format` (p. ej. "png"/"jpeg") creando un fichero nuevo por imagen.
    static func convert(_ urls: [URL], to format: String, extraArgs: [String] = []) -> Result {
        let suffix = format == "jpeg" ? "-jpg" : "-\(format)"
        let ext = format == "jpeg" ? "jpg" : format
        var created: [URL] = []
        var failures = 0
        for source in urls {
            let target = uniqueURL(for: source, suffix: suffix, ext: ext)
            var args = ["-s", "format", format]
            args.append(contentsOf: extraArgs)
            args.append(contentsOf: [source.path, "--out", target.path])
            let outcome = run("/usr/bin/sips", args)
            if outcome.code == 0 {
                created.append(target)
            } else {
                failures += 1
            }
        }
        return Result(created: created, failures: failures)
    }

    /// Redimensiona al 50 % (lado mayor/2) creando un fichero nuevo por imagen.
    static func resizeHalf(_ urls: [URL]) -> Result {
        var created: [URL] = []
        var failures = 0
        for source in urls {
            guard let size = pixelSize(of: source), size.width > 1, size.height > 1 else {
                failures += 1
                continue
            }
            let maxSide = max(size.width, size.height)
            let target = uniqueURL(for: source, suffix: "-50%", ext: nil)
            let outcome = run("/usr/bin/sips", ["-Z", String(Int(maxSide / 2.0)), source.path, "--out", target.path])
            if outcome.code == 0 {
                created.append(target)
            } else {
                failures += 1
            }
        }
        return Result(created: created, failures: failures)
    }

    /// URL de JUST4PICT si está instalada (bundle `com.dmx83.just4pict`).
    static var just4PictAppURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.dmx83.just4pict")
    }

    static func pixelSize(of url: URL) -> (width: CGFloat, height: CGFloat)? {
        let outcome = run("/usr/bin/sips", ["-g", "pixelWidth", "-g", "pixelHeight", url.path])
        guard outcome.code == 0 else { return nil }
        var width: CGFloat?
        var height: CGFloat?
        for line in outcome.output.split(separator: "\n") {
            let parts = line.split(separator: ":")
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            if key == "pixelWidth" { width = CGFloat(Double(value) ?? 0) }
            if key == "pixelHeight" { height = CGFloat(Double(value) ?? 0) }
        }
        guard let w = width, let h = height else { return nil }
        return (w, h)
    }

    static func uniqueURL(for source: URL, suffix: String, ext: String?) -> URL {
        let directory = source.deletingLastPathComponent()
        let base = source.deletingPathExtension().lastPathComponent
        let resolvedExtension = ext ?? source.pathExtension.lowercased()
        func candidate(_ name: String) -> URL {
            resolvedExtension.isEmpty
                ? directory.appendingPathComponent(name)
                : directory.appendingPathComponent("\(name).\(resolvedExtension)")
        }
        var url = candidate("\(base)\(suffix)")
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = candidate("\(base)\(suffix) \(counter)")
            counter += 1
        }
        return url
    }

    private static func run(_ launchPath: String, _ arguments: [String]) -> (code: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
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
