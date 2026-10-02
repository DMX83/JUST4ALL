import AppKit

/// Qué pasó al intentar abrir una subapp desde fuera de la ventana.
enum SubAppOpenOutcome: Equatable {
    /// Había una .app instalada y se abrió.
    case opened
    /// No estaba instalada: se lanzó desde el código del repo (modo desarrollo).
    case openedFromSource
    /// No hay .app ni código a mano: hay que instalarla desde el hub.
    case needsInstall
}

/// Localiza, lanza y trae al frente las apps del ecosistema JUST4ALL.
///
/// La usan los tres sitios desde los que se puede abrir una subapp: el botón «Abrir» de la
/// ventana, el menú del clic derecho del icono del Dock y el icono de la barra de menús.
enum SubAppLauncher {
    /// Identificador de la ventana principal (para `openWindow(id:)`).
    static let mainWindowID = "principal"

    // MARK: - Localizar

    /// Rutas donde se busca una subapp instalada, en orden de preferencia.
    static func candidateAppPaths(for app: SubApp, homeDirectory: String = NSHomeDirectory()) -> [String] {
        [
            "/Applications/\(app.name).app",
            "\(homeDirectory)/Applications/\(app.name).app"
        ]
    }

    /// La .app **instalada**: sólo cuenta lo que está en `/Applications` o `~/Applications`.
    ///
    /// Antes se preguntaba primero a LaunchServices, que también conoce los bundles del repo y
    /// los de un DMG montado: así el hub decía «6 instaladas» sin haber instalado ninguna.
    static func installedAppURL(for app: SubApp, homeDirectory: String = NSHomeDirectory()) -> URL? {
        for path in candidateAppPaths(for: app, homeDirectory: homeDirectory)
        where FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleId),
           isInsideApplications(path: url.path, homeDirectory: homeDirectory) {
            return url
        }
        return nil
    }

    /// Cualquier copia que el Mac conozca, esté donde esté (el repo, un DMG montado…).
    static func knownAppURL(for app: SubApp) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleId)
    }

    /// Versión de la copia conocida, aunque no esté instalada.
    static func knownVersion(of app: SubApp) -> String? {
        guard let url = knownAppURL(for: app) else { return nil }
        return version(at: url)
    }

    /// ¿Esta ruta es una app instalada de verdad (en las carpetas de aplicaciones)?
    static func isInsideApplications(path: String, homeDirectory: String = NSHomeDirectory()) -> Bool {
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        return normalized.hasPrefix("/Applications/")
            || normalized.hasPrefix(homeDirectory + "/Applications/")
    }

    static func isInstalled(_ app: SubApp, homeDirectory: String = NSHomeDirectory()) -> Bool {
        installedAppURL(for: app, homeDirectory: homeDirectory) != nil
    }

    /// Versión que declara la .app instalada, si la hay.
    ///
    /// Es lo que permite decir «tienes la 2.3.15 y hay una más nueva»: la versión del catálogo
    /// es la del hub, así que para saber qué hay en el Mac hay que leer el bundle.
    static func installedVersion(of app: SubApp, homeDirectory: String = NSHomeDirectory()) -> String? {
        guard let url = installedAppURL(for: app, homeDirectory: homeDirectory) else { return nil }
        return version(at: url)
    }

    /// Lee `CFBundleShortVersionString` del bundle (funciona con .app dentro de un DMG, en
    /// /Applications o en una carpeta temporal).
    static func version(at appURL: URL) -> String? {
        let infoPlist = appURL.appendingPathComponent("Contents/Info.plist")
        guard
            let data = try? Data(contentsOf: infoPlist),
            let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
            let dictionary = object as? [String: Any]
        else {
            return nil
        }
        return dictionary["CFBundleShortVersionString"] as? String
    }

    // MARK: - Abrir

    /// Abre la subapp. Si no está instalada, intenta el modo desarrollo y, si tampoco hay
    /// código a mano, se lo pide al hub (que la selecciona y ofrece la descarga).
    @discardableResult
    static func open(_ app: SubApp, fallbackToHub: Bool = true) -> SubAppOpenOutcome {
        if let url = installedAppURL(for: app) ?? knownAppURL(for: app) {
            openInstalled(url, bundleId: app.bundleId)
            return .opened
        }
        if launchFromSource(app) {
            return .openedFromSource
        }
        if fallbackToHub {
            HubBridge.shared.select(app)
            revealMainWindow()
        }
        return .needsInstall
    }

    /// Abre la .app y, si al segundo no hay proceso vivo, reintenta (a veces LaunchServices
    /// se queda en el intento y no pasa nada visible).
    static func openInstalled(_ url: URL, bundleId: String) {
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
            if error != nil {
                _ = NSWorkspace.shared.open(url)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).isEmpty {
                    _ = NSWorkspace.shared.open(url)
                }
            }
        }
    }

    /// Lanza la subapp desde el repo en modo desarrollo: el binario de Debug si ya existe,
    /// o `swift run` en su carpeta.
    @discardableResult
    static func launchFromSource(_ app: SubApp, repoRoots: [URL]? = nil) -> Bool {
        guard let appDir = sourceDirectory(for: app, repoRoots: repoRoots) else { return false }

        if let binary = debugBinaryURL(in: appDir, appName: app.name) {
            let process = Process()
            process.executableURL = binary
            process.currentDirectoryURL = appDir
            if (try? process.run()) != nil { return true }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swift", "run", app.name]
        process.currentDirectoryURL = appDir
        return (try? process.run()) != nil
    }

    /// Carpeta `APPS/<app>` del repo, si está a mano.
    static func sourceDirectory(for app: SubApp, repoRoots: [URL]? = nil) -> URL? {
        for root in repoRoots ?? repositoryRootCandidates() {
            let candidate = root.appendingPathComponent("APPS/\(app.name)", isDirectory: true)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    /// Candidatos a raíz del repo: el directorio de trabajo y, desde la app instalada (donde
    /// el directorio de trabajo es «/»), los sitios donde suele vivir el repo.
    static func repositoryRootCandidates(homeDirectory: String = NSHomeDirectory()) -> [URL] {
        var roots: [URL] = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true),
            URL(fileURLWithPath: homeDirectory + "/Repos/JUST4ALL", isDirectory: true),
            URL(fileURLWithPath: homeDirectory + "/Developer/JUST4ALL", isDirectory: true)
        ]

        var cursor = Bundle.main.bundleURL.standardizedFileURL
        for _ in 0..<8 {
            cursor.deleteLastPathComponent()
            roots.append(cursor)
        }

        var seen = Set<String>()
        return roots.filter { url in
            let path = url.standardizedFileURL.path
            if seen.contains(path) { return false }
            seen.insert(path)
            return true
        }
    }

    static func debugBinaryURL(in appDir: URL, appName: String) -> URL? {
        let names = [
            ".build/arm64-apple-macosx/debug/\(appName)",
            ".build/x86_64-apple-macosx/debug/\(appName)",
            ".build/debug/\(appName)"
        ]
        for relative in names {
            let candidate = appDir.appendingPathComponent(relative)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    // MARK: - La ventana del hub

    /// Trae al frente la ventana del hub y, si no queda ninguna (se cerró), le pide al Mac
    /// que la vuelva a abrir: es lo mismo que abrir la app otra vez.
    static func revealMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
            return
        }
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: .init()) { _, _ in }
    }
}
