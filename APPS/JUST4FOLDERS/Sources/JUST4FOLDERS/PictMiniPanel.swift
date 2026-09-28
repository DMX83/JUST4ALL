import AppKit

/// v2.3.2 (Panel Hub F3) — Módulo «PICT mini»: acciones rápidas sobre la imagen (o imágenes)
/// seleccionada en el panel activo.
///
/// No reescribe el pipeline de JUST4PICT: usa `sips` (herramienta nativa de macOS) para
/// conversiones y redimensionado. **Nunca sobrescribe**: cada acción crea un fichero NUEVO
/// junto al original con sufijo («-png», «-jpg», «-50%»). Si JUST4PICT está instalada, ofrece
/// abrir la selección en ella.
final class PictMiniPanelView: NSView {

    /// Mensajes de estado para la barra del commander.
    var onStatus: ((String) -> Void)?
    /// Tras crear ficheros (el commander refresca paneles).
    var onCreatedFiles: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "PICT · ACCIONES RÁPIDAS")
    private let nameLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let pngButton = NSButton()
    private let jpegButton = NSButton()
    private let halfButton = NSButton()
    private let openButton = NSButton()

    private var selection: [URL] = []

    private static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "tiff", "tif", "webp", "gif", "bmp"
    ]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        buildUI()
        updateSelection([])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) no soportado")
    }

    // MARK: - Construcción

    private func buildUI() {
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 10.5, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .systemFont(ofSize: 12)
        nameLabel.lineBreakMode = .byTruncatingMiddle

        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.font = .systemFont(ofSize: 10.5)
        detailLabel.textColor = .tertiaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingMiddle
        detailLabel.maximumNumberOfLines = 2

        configure(pngButton, title: "Convertir a PNG", action: #selector(onPNGClicked))
        configure(jpegButton, title: "Convertir a JPEG", action: #selector(onJPEGClicked))
        configure(halfButton, title: "Redimensionar 50 %", action: #selector(onHalfClicked))
        configure(openButton, title: "Abrir en JUST4PICT", action: #selector(onOpenPICTClicked))
        openButton.toolTip = "Abre la selección en JUST4PICT (debe estar instalada)"

        let row1 = NSStackView(views: [pngButton, jpegButton])
        row1.orientation = .horizontal
        row1.spacing = 6
        row1.translatesAutoresizingMaskIntoConstraints = false

        let row2 = NSStackView(views: [halfButton, openButton])
        row2.orientation = .horizontal
        row2.spacing = 6
        row2.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleLabel)
        addSubview(nameLabel)
        addSubview(detailLabel)
        addSubview(row1)
        addSubview(row2)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),

            nameLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor),

            detailLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 3),
            detailLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: trailingAnchor),

            row1.topAnchor.constraint(equalTo: detailLabel.bottomAnchor, constant: 10),
            row1.leadingAnchor.constraint(equalTo: leadingAnchor),

            row2.topAnchor.constraint(equalTo: row1.bottomAnchor, constant: 6),
            row2.leadingAnchor.constraint(equalTo: leadingAnchor)
        ])
    }

    private func configure(_ button: NSButton, title: String, action: Selector) {
        button.title = title
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    // MARK: - Selección

    /// Actualiza la selección del panel activo (solo imágenes soportadas).
    func updateSelection(_ urls: [URL]) {
        selection = urls.filter { Self.imageExtensions.contains($0.pathExtension.lowercased()) }
        let enabled = !selection.isEmpty
        pngButton.isEnabled = enabled
        jpegButton.isEnabled = enabled
        halfButton.isEnabled = enabled
        openButton.isEnabled = enabled

        if selection.isEmpty {
            nameLabel.stringValue = "Selecciona una imagen en un panel"
            detailLabel.stringValue = urls.isEmpty
                ? "Conversiones y redimensionado con sips (crea un fichero nuevo, nunca sobrescribe)."
                : "La selección actual no es de imágenes soportadas (jpg, png, heic, tiff, webp…)."
        } else if selection.count == 1 {
            nameLabel.stringValue = selection[0].lastPathComponent
            detailLabel.stringValue = "Conversiones y redimensionado con sips; no sobrescribe el original."
        } else {
            nameLabel.stringValue = "\(selection.count) imágenes seleccionadas"
            detailLabel.stringValue = "Se procesarán todas; cada una crea un fichero nuevo."
        }
    }

    // MARK: - Acciones

    @objc private func onPNGClicked() {
        convertAll(to: "png", suffix: "-png")
    }

    @objc private func onJPEGClicked() {
        convertAll(to: "jpeg", suffix: "-jpg", extraArgs: ["-s", "formatOptions", "85"])
    }

    @objc private func onHalfClicked() {
        guard !selection.isEmpty else { return }
        var created: [URL] = []
        var failures = 0
        for source in selection {
            guard let size = Self.pixelSize(of: source), size.width > 1, size.height > 1 else {
                failures += 1
                continue
            }
            let maxSide = max(size.width, size.height)
            let target = uniqueURL(for: source, suffix: "-50%", extension: nil)
            let result = Self.run("/usr/bin/sips", ["-Z", String(Int(maxSide / 2.0)), source.path, "--out", target.path])
            if result.code == 0 {
                created.append(target)
            } else {
                failures += 1
            }
        }
        finish(created: created, failures: failures, action: "redimensionadas al 50 %")
    }

    @objc private func onOpenPICTClicked() {
        guard !selection.isEmpty else { return }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.dmx83.just4pict") else {
            onStatus?("JUST4PICT no está instalada (no se encontró com.dmx83.just4pict).")
            NSSound.beep()
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open(selection, withApplicationAt: appURL, configuration: configuration) { [weak self] _, error in
            if let error {
                self?.onStatus?("No se pudo abrir en JUST4PICT: \(error.localizedDescription)")
            } else {
                self?.onStatus?("Abierto en JUST4PICT (\(self?.selection.count ?? 0) fichero(s)).")
            }
        }
    }

    private func convertAll(to format: String, suffix: String, extraArgs: [String] = []) {
        guard !selection.isEmpty else { return }
        var created: [URL] = []
        var failures = 0
        for source in selection {
            let target = uniqueURL(for: source, suffix: suffix, extension: format == "jpeg" ? "jpg" : format)
            var args = ["-s", "format", format]
            args.append(contentsOf: extraArgs)
            args.append(contentsOf: [source.path, "--out", target.path])
            let result = Self.run("/usr/bin/sips", args)
            if result.code == 0 {
                created.append(target)
            } else {
                failures += 1
            }
        }
        finish(created: created, failures: failures, action: "convertidas a \(format.uppercased())")
    }

    private func finish(created: [URL], failures: Int, action: String) {
        if !created.isEmpty {
            onCreatedFiles?()
        }
        if failures == 0 {
            onStatus?("PICT: \(created.count) imagen(es) \(action). Se creó un fichero nuevo junto al original.")
        } else {
            onStatus?("PICT: \(created.count) \(action); \(failures) fallo(s).")
        }
        updateSelection(selection) // refresca subtítulo
    }

    // MARK: - Utilidades

    private static func pixelSize(of url: URL) -> (width: CGFloat, height: CGFloat)? {
        let result = run("/usr/bin/sips", ["-g", "pixelWidth", "-g", "pixelHeight", url.path])
        guard result.code == 0 else { return nil }
        var width: CGFloat?
        var height: CGFloat?
        for line in result.output.split(separator: "\n") {
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

    private func uniqueURL(for source: URL, suffix: String, extension ext: String?) -> URL {
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
