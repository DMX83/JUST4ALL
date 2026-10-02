import SwiftUI

/// Todo el lenguaje visual del hub en un solo sitio: escala de tipografía, medidas y las
/// piezas que comparten la rejilla y el panel de detalle.
///
/// Antes cada vista mezclaba Avenir Next con la fuente del sistema y colores sueltos, y las
/// tarjetas se estiraban a capricho según el texto. Aquí sólo hay una escala y una medida.
enum HubDesign {
    // MARK: - Tipografía

    /// El nombre del hub (lo único con la fuente de marca).
    static let wordmark = Font.system(size: 27, weight: .bold, design: .rounded)
    /// Título dentro del panel de detalle.
    static let title = Font.system(size: 16, weight: .semibold)
    /// Nombre de la app en su tarjeta.
    static let cardTitle = Font.system(size: 14.5, weight: .semibold)
    /// Texto corrido.
    static let body = Font.system(size: 12.5)
    /// Etiquetas y distintivos.
    static let label = Font.system(size: 11, weight: .semibold)
    /// Notas al pie.
    static let caption = Font.system(size: 11)
    /// Versiones y identificadores.
    static let mono = Font.system(size: 11, design: .monospaced)

    // MARK: - Medidas

    /// Ancho mínimo de una tarjeta: la rejilla mete las columnas que quepan.
    static let cardMinWidth: CGFloat = 268
    /// Alto de la tarjeta: todas iguales, para que la rejilla no baile.
    static let cardHeight: CGFloat = 116
    /// Ancho del panel de detalle.
    static let detailWidth: CGFloat = 368
    static let corner: CGFloat = 14
}

// MARK: - Estado de una subapp

/// En qué situación está una subapp en este Mac, que es lo que se enseña (y lo que decide
/// si el botón pone «Abrir», «Descargar» o «Actualizar»).
///
/// «Instalada» es estar en /Applications: que LaunchServices conozca un bundle del repo o de
/// un DMG montado no es estar instalada (ese matiz hacía que el hub dijera «6 instaladas»).
enum SubAppState: Equatable {
    /// En /Applications (o ~/Applications) y al día.
    case installed(version: String)
    /// Hay copia en el Mac (el repo, un DMG), pero no está instalada.
    case localCopy(version: String)
    /// Instalada, y además hay una versión más nueva publicada.
    case updateAvailable(installed: String, published: String)
    /// No hay nada de esta app en el Mac.
    case notInstalled

    /// ¿Está instalada de verdad (en /Applications)?
    var isInstalledInApplications: Bool {
        switch self {
        case .installed, .updateAvailable: return true
        case .localCopy, .notInstalled: return false
        }
    }

    /// ¿Se puede abrir algo sin descargar?
    var canOpen: Bool {
        if case .notInstalled = self { return false }
        return true
    }

    /// Etiqueta corta, para las tarjetas.
    var compactLabel: String {
        switch self {
        case .installed: return "Instalada"
        case .localCopy: return "Copia local"
        case .updateAvailable: return "Actualización"
        case .notInstalled: return "Sin instalar"
        }
    }

    /// Etiqueta completa, para el panel.
    var label: String {
        switch self {
        case .installed(let version): return "Instalada · v\(version)"
        case .localCopy(let version): return "Copia en el Mac (sin instalar) · v\(version)"
        case .updateAvailable(let installed, let published): return "Actualizar: v\(installed) → v\(published)"
        case .notInstalled: return "Sin instalar"
        }
    }

    var symbol: String {
        switch self {
        case .installed: return "checkmark.circle.fill"
        case .localCopy: return "folder.circle"
        case .updateAvailable: return "arrow.down.circle.fill"
        case .notInstalled: return "circle.dashed"
        }
    }

    var color: Color {
        switch self {
        case .installed: return .green
        case .localCopy: return .orange
        case .updateAvailable: return .accentColor
        case .notInstalled: return .secondary
        }
    }

    /// Decide el estado con lo instalado en /Applications, la copia que haya por el Mac y lo
    /// publicado en GitHub.
    ///
    /// Si la versión instalada no se puede leer, se dice «sin instalar» en vez de inventarse
    /// nada; si la publicada no se entiende, se da por buena la instalada.
    static func resolve(
        installedVersion: String?,
        localVersion: String?,
        publishedVersion: String?
    ) -> SubAppState {
        if let installedVersion {
            if let publishedVersion,
               let installed = SemVer(installedVersion),
               let published = SemVer(publishedVersion),
               published > installed {
                return .updateAvailable(installed: installedVersion, published: publishedVersion)
            }
            return .installed(version: installedVersion)
        }
        if let localVersion {
            return .localCopy(version: localVersion)
        }
        return .notInstalled
    }
}

// MARK: - Piezas compartidas

/// Distintivo de estado: color + icono + palabra (nunca sólo el color).
struct StateBadge: View {
    let state: SubAppState
    var compact = false

    var body: some View {
        Label(compact ? state.compactLabel : state.label, systemImage: state.symbol)
            .font(HubDesign.label)
            .foregroundStyle(state.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(state.color.opacity(0.13)))
            .lineLimit(1)
            .accessibilityLabel(state.label)
    }
}

/// Icono de una subapp dentro de su recuadro de color.
struct IconTile: View {
    let symbol: String
    let accent: Color
    var size: CGFloat = HubDesign.cardHeight * 0.34

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(accent.opacity(0.16))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .strokeBorder(accent.opacity(0.30), lineWidth: 1)
            )
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundStyle(accent)
            )
            .frame(width: size, height: size)
    }
}

/// Aviso corto del hub: lo último que ha pasado (arriba a la derecha).
struct HubStatusPill: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "info.circle")
            .font(HubDesign.label)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(.quaternary.opacity(0.55)))
            .overlay(Capsule().strokeBorder(.primary.opacity(0.06)))
    }
}

/// Bloque del panel de detalle: título con icono y contenido.
struct DetailSection<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: symbol)
                .font(HubDesign.label)
                .foregroundStyle(.secondary)
            content
        }
    }
}

/// Dato con su etiqueta («En este Mac: 2.3.15»), como en los paneles del sistema.
struct FactRow: View {
    let label: String
    let value: String
    var accent: Color?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(HubDesign.caption)
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            Text(value)
                .font(HubDesign.body)
                .foregroundStyle(accent ?? .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}

/// Fondo de la ventana: un degradado suave que respeta el modo claro y oscuro.
struct HubBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: scheme == .dark
                    ? [Color(red: 0.11, green: 0.12, blue: 0.14), Color(red: 0.07, green: 0.08, blue: 0.11)]
                    : [Color(red: 0.96, green: 0.97, blue: 0.98), Color(red: 0.90, green: 0.94, blue: 0.99)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color.accentColor.opacity(scheme == .dark ? 0.12 : 0.07))
                .frame(width: 460, height: 460)
                .blur(radius: 45)
                .offset(x: -330, y: -250)

            Circle()
                .fill(Color(red: 0.18, green: 0.67, blue: 0.47).opacity(scheme == .dark ? 0.09 : 0.06))
                .frame(width: 400, height: 400)
                .blur(radius: 45)
                .offset(x: 370, y: 310)
        }
    }
}
