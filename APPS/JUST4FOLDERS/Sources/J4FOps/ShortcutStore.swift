import Foundation

/// v2.0 — Atajos configurables: almacén JSON con los comandos del monitor de teclado.
/// `all()` devuelve los valores por defecto salvo los que el usuario haya cambiado.
public struct ShortcutBinding: Codable, Sendable, Equatable {
    public var command: String
    public var keyCode: UInt16
    public var cmd: Bool
    public var opt: Bool
    public var shift: Bool
    public var ctrl: Bool

    public init(command: String, keyCode: UInt16, cmd: Bool = false, opt: Bool = false, shift: Bool = false, ctrl: Bool = false) {
        self.command = command
        self.keyCode = keyCode
        self.cmd = cmd
        self.opt = opt
        self.shift = shift
        self.ctrl = ctrl
    }

    /// «⌥⌘T», «F5», … para mostrar en la UI.
    public var displayString: String {
        var parts = ""
        if ctrl { parts += "⌃" }
        if opt { parts += "⌥" }
        if shift { parts += "⇧" }
        if cmd { parts += "⌘" }
        return parts + Self.keyName(keyCode)
    }

    static func keyName(_ keyCode: UInt16) -> String {
        let special: [UInt16: String] = [
            0: "A", 9: "V", 13: "W", 17: "T", 1: "S", 3: "F", 40: "K",
            96: "F5", 97: "F6", 98: "F7", 100: "F8", 99: "F3", 118: "F4", 120: "F2"
        ]
        return special[keyCode] ?? "#\(keyCode)"
    }
}

public final class ShortcutStore {
    public static let shared = ShortcutStore()

    public static let defaults: [ShortcutBinding] = [
        ShortcutBinding(command: "rename", keyCode: 120),
        ShortcutBinding(command: "quickLook", keyCode: 99),
        ShortcutBinding(command: "openEdit", keyCode: 118),
        ShortcutBinding(command: "copy", keyCode: 96),
        ShortcutBinding(command: "move", keyCode: 97),
        ShortcutBinding(command: "mkdir", keyCode: 98),
        ShortcutBinding(command: "delete", keyCode: 100),
        ShortcutBinding(command: "newTab", keyCode: 17, cmd: true),
        ShortcutBinding(command: "closeTab", keyCode: 13, cmd: true),
        ShortcutBinding(command: "selectAll", keyCode: 0, cmd: true),
        ShortcutBinding(command: "paste", keyCode: 9, cmd: true),
        ShortcutBinding(command: "duplicateTab", keyCode: 17, cmd: true, opt: true)
    ]

    /// Nombres para la UI del editor.
    public static let displayNames: [String: String] = [
        "rename": "Renombrar elemento",
        "quickLook": "QuickLook (vista rápida)",
        "openEdit": "Abrir (editar)",
        "copy": "Copiar al otro panel",
        "move": "Mover al otro panel",
        "mkdir": "Nueva carpeta",
        "delete": "Enviar a la Papelera",
        "newTab": "Nueva pestaña",
        "closeTab": "Cerrar pestaña",
        "selectAll": "Seleccionar todo",
        "paste": "Pegar",
        "duplicateTab": "Duplicar pestaña"
    ]

    private let url: URL
    private var overrides: [String: ShortcutBinding] = [:]

    public static func defaultURL(appFolder: String = "JUST4FOLDERS") -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base
            .appendingPathComponent(appFolder, isDirectory: true)
            .appendingPathComponent("shortcuts.json", isDirectory: false)
    }

    public init(url: URL? = nil) {
        self.url = url ?? Self.defaultURL()
        load()
    }

    /// Todas las combinaciones efectivas (por defecto + cambios del usuario).
    public func all() -> [ShortcutBinding] {
        Self.defaults.map { overrides[$0.command] ?? $0 }
    }

    /// Comando para una pulsación concreta (nil si no hay coincidencia).
    public func command(keyCode: UInt16, flags: (cmd: Bool, opt: Bool, shift: Bool, ctrl: Bool)) -> String? {
        for binding in all()
        where binding.keyCode == keyCode
            && binding.cmd == flags.cmd
            && binding.opt == flags.opt
            && binding.shift == flags.shift
            && binding.ctrl == flags.ctrl {
            return binding.command
        }
        return nil
    }

    public func set(_ binding: ShortcutBinding) {
        overrides[binding.command] = binding
        persist()
    }

    public func resetAll() {
        overrides.removeAll()
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: ShortcutBinding].self, from: data) else { return }
        overrides = decoded
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(overrides)
            try data.write(to: url, options: .atomic)
        } catch {
            // Comodidad: un fallo de escritura no debe afectar al uso normal.
        }
    }
}
