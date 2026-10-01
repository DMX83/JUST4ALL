import SwiftUI

enum SubAppHistoryAction: String, Codable {
    case opened
    case downloaded
}

struct SubAppHistoryEntry: Codable, Hashable, Identifiable {
    let id: UUID
    let version: String
    let action: SubAppHistoryAction
    let date: Date
}

struct SubAppHistoryStore {
    private let defaults: UserDefaults
    private let keyPrefix = "just4all.history."
    private let maxEntries = 8

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func history(for app: SubApp) -> [SubAppHistoryEntry] {
        let key = storageKey(for: app)
        guard let data = defaults.data(forKey: key) else {
            return []
        }
        return (try? JSONDecoder().decode([SubAppHistoryEntry].self, from: data)) ?? []
    }

    func record(_ action: SubAppHistoryAction, for app: SubApp, version: String? = nil) {
        var entries = history(for: app)
        let entry = SubAppHistoryEntry(id: UUID(), version: version ?? app.version, action: action, date: Date())
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        save(entries, for: app)
    }

    private func save(_ entries: [SubAppHistoryEntry], for app: SubApp) {
        let key = storageKey(for: app)
        guard let data = try? JSONEncoder().encode(entries) else {
            return
        }
        defaults.set(data, forKey: key)
    }

    private func storageKey(for app: SubApp) -> String {
        keyPrefix + app.bundleId
    }
}

struct SubApp: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let subtitle: String
    let bundleId: String
    let assetPrefix: String
    let accent: Color
    let systemIcon: String
    let description: String
    let requirements: [String]
    let links: [SubAppLink]
    let version: String
    let changelog: [String]
    let logoName: String
    let screenshots: [String]
}

struct SubAppLink: Identifiable, Hashable {
    let id = UUID()
    let label: String
    let url: String
}

enum SubAppsCatalog {
    private static let pinnedVersion = AppInfo.suiteVersion
    private static let pinnedReleaseTag = AppInfo.suiteReleaseTag

    static let items: [SubApp] = [
        SubApp(
            name: "JUST4PDF",
            subtitle: "PDF reader y herramientas",
            bundleId: "com.dmx83.just4pdf",
            assetPrefix: "JUST4PDF",
            accent: Color(red: 0.12, green: 0.45, blue: 0.86),
            systemIcon: "doc.richtext",
            description: "Lee y organiza PDFs, exporta imagenes y usa herramientas basicas de PDF.",
            requirements: ["macOS 13+", "Instalado como .app"],
            links: [],
            version: pinnedVersion,
            changelog: [
                "MVP con lectura y utilidades basicas",
                "Instalacion local desde JUST4ALL"
            ],
            logoName: "Assets/JUST4PDF/logo.png",
            screenshots: [
                "Assets/JUST4PDF/screen-1.png",
                "Assets/JUST4PDF/screen-2.png"
            ]
        ),
        SubApp(
            name: "JUST4CONVERT",
            subtitle: "Convertidor de audio, video e imagenes",
            bundleId: "com.dmx83.just4convert",
            assetPrefix: "JUST4CONVERT",
            accent: Color(red: 0.18, green: 0.67, blue: 0.47),
            systemIcon: "arrow.triangle.2.circlepath",
            description: "Convierte audio, video e imagenes con presets simples y salida rapida.",
            requirements: ["macOS 13+", "Instalado como .app"],
            links: [],
            version: pinnedVersion,
            changelog: [
                "MVP nativo con conversion basica",
                "Cola simple y presets iniciales"
            ],
            logoName: "Assets/JUST4CONVERT/logo.png",
            screenshots: [
                "Assets/JUST4CONVERT/screen-1.png",
                "Assets/JUST4CONVERT/screen-2.png"
            ]
        ),
        SubApp(
            name: "JUST4FOLDERS",
            subtitle: "Organizador de carpetas y archivos",
            bundleId: "com.dmx83.just4folders",
            assetPrefix: "JUST4FOLDERS",
            accent: Color(red: 0.88, green: 0.52, blue: 0.18),
            systemIcon: "folder.badge.gearshape",
            description: "Analiza carpetas y organiza archivos por categoria en una estructura de destino limpia.",
            requirements: ["macOS 13+", "Instalado como .app"],
            links: [],
            version: pinnedVersion,
            changelog: [
                "MVP con analisis recursivo por categoria",
                "Organizacion por copia con progreso y colisiones"
            ],
            logoName: "Assets/JUST4FOLDERS/logo.png",
            screenshots: [
                "Assets/JUST4FOLDERS/screen-1.png",
                "Assets/JUST4FOLDERS/screen-2.png"
            ]
        ),
        SubApp(
            name: "JUST4PICT",
            subtitle: "Mejoramiento automatico de imagenes",
            bundleId: "com.dmx83.just4pict",
            assetPrefix: "JUST4PICT",
            accent: Color(red: 0.59, green: 0.33, blue: 0.92),
            systemIcon: "wand.and.stars",
            description: "Mejora imagenes por lotes con presets automaticos para retrato, documento, ecommerce y mas.",
            requirements: ["macOS 13+", "Instalado como .app"],
            links: [],
            version: pinnedVersion,
            changelog: [
                "MVP con mejoras automaticas por lotes",
                "Export a JPG/PNG/HEIC/WEBP/TIFF"
            ],
            logoName: "Assets/JUST4PICT/logo.png",
            screenshots: [
                "Assets/JUST4PICT/screen-1.png",
                "Assets/JUST4PICT/screen-2.png"
            ]
        ),
        SubApp(
            name: "JUST4DESK",
            subtitle: "Tu escritorio inteligente: ordena, encuentra y protege tu documentación",
            bundleId: "com.dmx83.just4desk",
            assetPrefix: "JUST4DESK",
            accent: Color(red: 0.35, green: 0.34, blue: 0.84),
            systemIcon: "desktopcomputer",
            description: "Tu escritorio inteligente para Mac: encuentra cualquier archivo en milisegundos y deja que ordene tus carpetas solo — clasifica por contenido con IA opcional, aprende de tus correcciones y archiva con undo; lo dudoso queda en «sin clasificar» para revisarlo. Nunca borra: solo mueve. Todo en tu Mac.",
            requirements: ["macOS 14+", "Instalado como .app"],
            links: [],
            version: pinnedVersion,
            changelog: [
                "Nuevo nombre y marca: tu escritorio inteligente de documentos",
                "Buscador instantaneo con indice local (FTS5 + FSEvents; subcadena y contenido)",
                "Organizador automatico con taxonomia fina y cola «sin clasificar» revisable; aprende de tus correcciones"
            ],
            logoName: "Assets/JUST4DESK/logo.png",
            screenshots: [
                "Assets/JUST4DESK/screen-1.png",
                "Assets/JUST4DESK/screen-2.png"
            ]
        ),
        SubApp(
            name: "LIFEOS",
            subtitle: "Tu organizador personal, en el Mac",
            bundleId: "com.dmx83.lifeos",
            assetPrefix: "LIFEOS",
            accent: Color(red: 0.37, green: 0.36, blue: 0.85),
            systemIcon: "target",
            description: "Captura lo que se te ocurre, confirma lo que LifeOS propone, mira como va tu dia y cierra la jornada. Atajo global, menu de barra y avisos del sistema aunque la app este en segundo plano, y capturas sin conexion que se envian solas. Necesita tu cuenta y tu servidor de LifeOS (lifeos.perlatec.net o el de tu red local).",
            requirements: ["macOS 14+", "Cuenta y servidor de LifeOS", "Google o usuario y contrasena"],
            links: [
                SubAppLink(label: "Consola web de LifeOS", url: "https://lifeos.perlatec.net")
            ],
            version: pinnedVersion,
            changelog: [
                "Cliente nativo del ciclo diario sobre la API de LifeOS",
                "Acceso con Google igual que la web, o usuario y contrasena con verificacion en dos pasos",
                "Captura con propuesta revisable: nada se guarda sin tu confirmacion",
                "Avisos del sistema y captura sin conexion que se envia sola"
            ],
            logoName: "Assets/LIFEOS/logo.png",
            screenshots: [
                "Assets/LIFEOS/screen-1.png",
                "Assets/LIFEOS/screen-2.png"
            ]
        )
    ]

    static func pinnedDownloadURL(for app: SubApp) -> URL? {
        let base = AppInfo.githubReleaseDownloadBaseURL
        return URL(string: base + pinnedReleaseTag + "/\(app.assetPrefix)-\(pinnedVersion).dmg")
    }

    static func pinnedFileName(for app: SubApp) -> String {
        "\(app.assetPrefix)-\(pinnedVersion).dmg"
    }
}
