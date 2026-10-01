import Foundation

/// Ajustes de la app. Se guardan en `UserDefaults` porque no son secretos: el
/// token vive en el llavero.
public final class SettingsStore {
    public static let defaultBaseURLString = "https://lifeos.perlatec.net"

    private enum Key {
        static let baseURL = "lifeos.baseURL"
        static let notifyReminders = "lifeos.notifyReminders"
        static let sensitiveByDefault = "lifeos.capture.sensitiveByDefault"
        static let hotKeyEnabled = "lifeos.hotKeyEnabled"
        static let launchAtLogin = "lifeos.launchAtLogin"
        static let inboxFilter = "lifeos.inbox.filter"
        static let lastPane = "lifeos.lastPane"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.baseURL: SettingsStore.defaultBaseURLString,
            Key.notifyReminders: true,
            Key.sensitiveByDefault: false,
            Key.hotKeyEnabled: true,
            Key.launchAtLogin: false,
            Key.inboxFilter: "pending",
            Key.lastPane: "today"
        ])
    }

    public var baseURLString: String {
        get { defaults.string(forKey: Key.baseURL) ?? SettingsStore.defaultBaseURLString }
        set { defaults.set(newValue, forKey: Key.baseURL) }
    }

    /// Dirección base ya normalizada (sin barra final, con esquema).
    public var baseURL: URL {
        SettingsStore.normalize(baseURLString) ?? URL(string: SettingsStore.defaultBaseURLString)!
    }

    public var notifyReminders: Bool {
        get { defaults.bool(forKey: Key.notifyReminders) }
        set { defaults.set(newValue, forKey: Key.notifyReminders) }
    }

    public var sensitiveByDefault: Bool {
        get { defaults.bool(forKey: Key.sensitiveByDefault) }
        set { defaults.set(newValue, forKey: Key.sensitiveByDefault) }
    }

    public var hotKeyEnabled: Bool {
        get { defaults.bool(forKey: Key.hotKeyEnabled) }
        set { defaults.set(newValue, forKey: Key.hotKeyEnabled) }
    }

    /// Abrir la app al iniciar sesión en el Mac. Se aplica con `SMAppService`
    /// (macOS 13+), no con la carpeta de inicio: así macOS lo enseña en
    /// «Ítems de inicio» y se puede desactivar desde ahí también.
    public var launchAtLogin: Bool {
        get { defaults.bool(forKey: Key.launchAtLogin) }
        set { defaults.set(newValue, forKey: Key.launchAtLogin) }
    }

    /// Filtro de la bandeja: `pending` o vacío (todo).
    public var inboxFilter: String {
        get { defaults.string(forKey: Key.inboxFilter) ?? "pending" }
        set { defaults.set(newValue, forKey: Key.inboxFilter) }
    }

    /// Última sección abierta: al volver a la app se sigue donde se estaba.
    public var lastPane: String? {
        get { defaults.string(forKey: Key.lastPane) }
        set { defaults.set(newValue, forKey: Key.lastPane) }
    }

    /// Acepta lo que la gente escribe de verdad: sin esquema, con barra final o
    /// con espacios. Devuelve `nil` si no hay forma de sacar una URL con host.
    public static func normalize(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.lowercased().hasPrefix("http://") && !text.lowercased().hasPrefix("https://") {
            text = "https://" + text
        }
        while text.hasSuffix("/") {
            text.removeLast()
        }
        guard let url = URL(string: text), url.host?.isEmpty == false else { return nil }
        return url
    }
}
