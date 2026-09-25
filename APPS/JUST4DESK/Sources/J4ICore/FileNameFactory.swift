import Foundation

/// Construcción y saneado de nombres de archivo archivado.
///
/// Plantilla: `YYYY-MM-DD_Emisor_Titulo.ext` (partes opcionales; si no hay ninguna,
/// se usa el nombre original saneado).
public enum FileNameFactory {
    public static let maxLength = 120

    public static func make(date: Date?, issuer: String?, title: String?, originalFileName: String) -> String {
        let ext = (originalFileName as NSString).pathExtension.lowercased()
        var parts: [String] = []
        if let date {
            parts.append(isoDateFormatter.string(from: date))
        }
        if let issuer, let cleaned = sanitizeComponent(issuer) {
            parts.append(cleaned)
        }
        if let title, let cleaned = sanitizeComponent(title) {
            parts.append(cleaned)
        }
        if parts.isEmpty {
            let base = (originalFileName as NSString).deletingPathExtension
            parts = [sanitizeComponent(base) ?? "documento"]
        }

        var name = parts.joined(separator: "_")
        if name.count > maxLength {
            name = String(name.prefix(maxLength))
            name = name.trimmingCharacters(in: CharacterSet(charactersIn: "_- ."))
        }
        if name.isEmpty {
            name = "documento"
        }
        return ext.isEmpty ? name : "\(name).\(ext)"
    }

    /// Sanea un segmento de nombre: quita caracteres ilegales, espacios → `-`,
    /// colapsa separadores duplicados y recorta bordes.
    public static func sanitizeComponent(_ value: String) -> String? {
        var s = value.precomposedStringWithCanonicalMapping
        for bad in ["/", ":", "\\", "*", "?", "\"", "<", ">", "|", "\n", "\r", "\t"] {
            s = s.replacingOccurrences(of: bad, with: "-")
        }
        s = s.replacingOccurrences(of: " ", with: "-")
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "-._"))
        while s.contains("--") { s = s.replacingOccurrences(of: "--", with: "-") }
        while s.contains("__") { s = s.replacingOccurrences(of: "__", with: "_") }
        while s.contains("-_-") { s = s.replacingOccurrences(of: "-_-", with: "_") }
        return s.isEmpty ? nil : s
    }

    private static let isoDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
