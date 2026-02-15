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
