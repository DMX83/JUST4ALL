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
        selection = PictQuickActions.images(in: urls)
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
        apply(PictQuickActions.convert(selection, to: "png"), verb: "convertidas a PNG")
    }

    @objc private func onJPEGClicked() {
        apply(
            PictQuickActions.convert(selection, to: "jpeg", extraArgs: ["-s", "formatOptions", "85"]),
            verb: "convertidas a JPEG"
        )
    }

    @objc private func onHalfClicked() {
        apply(PictQuickActions.resizeHalf(selection), verb: "redimensionadas al 50 %")
    }

    @objc private func onOpenPICTClicked() {
        guard !selection.isEmpty else { return }
        guard let appURL = PictQuickActions.just4PictAppURL else {
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

    private func apply(_ result: PictQuickActions.Result, verb: String) {
        if !result.created.isEmpty {
            onCreatedFiles?()
        }
        if result.failures == 0 {
            onStatus?("PICT: \(result.created.count) imagen(es) \(verb). Se creó un fichero nuevo junto al original.")
        } else {
            onStatus?("PICT: \(result.created.count) \(verb); \(result.failures) fallo(s).")
        }
        updateSelection(selection)
    }
}
