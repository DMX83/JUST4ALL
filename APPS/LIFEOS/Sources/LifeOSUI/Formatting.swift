import Foundation

/// Formatos de fecha y hora, en un solo sitio y en español.
public enum TimeFormatting {
    public static func time(_ date: Date) -> String {
        formatter("HH:mm").string(from: date)
    }

    /// «Hace 2 h», «ayer», «12 sep» — para listas donde la hora exacta no ayuda.
    public static func relative(_ date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "ahora" }
        if seconds < 3600 { return "hace \(Int(seconds / 60)) min" }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "hoy, " + time(date) }
        if calendar.isDateInYesterday(date) { return "ayer" }
        if seconds < 7 * 24 * 3600 { return "hace \(Int(seconds / 86400)) d" }
        return formatter("d MMM").string(from: date)
    }

    public static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// «miércoles, 30 de septiembre».
    public static func longDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return formatter.string(from: date)
    }

    /// «L», «M», «X»… para la tira de la semana.
    public static func weekdayLetter(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.setLocalizedDateFormatFromTemplate("EEEEE")
        return formatter.string(from: date)
    }

    /// El número del día del mes: «30».
    public static func dayNumber(_ date: Date) -> String {
        formatter("d").string(from: date)
    }

    /// «30 de septiembre», sin el día de la semana.
    public static func shortDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.setLocalizedDateFormatFromTemplate("dMMMM")
        return formatter.string(from: date)
    }

    /// «30 sep, 09:00».
    public static func dateAndTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.setLocalizedDateFormatFromTemplate("dMMMHHmm")
        return formatter.string(from: date)
    }

    /// Un vencimiento, en palabras: «hoy», «mañana», «ayer», «hace 3 d», «12 oct».
    public static func relativeDue(_ date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "hoy" }
        if calendar.isDateInTomorrow(date) { return "mañana" }
        if calendar.isDateInYesterday(date) { return "ayer" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        if days < 0 { return "hace \(-days) d" }
        if days <= 7 { return "en \(days) d" }
        return formatter("d MMM").string(from: date)
    }

    /// Convierte «2026-09-30» (fecha sin hora, como la manda la API).
    public static func day(from raw: String) -> Date? {
        formatter("yyyy-MM-dd").date(from: raw)
    }

    /// El inverso: el día de hoy como lo escribe la API («2026-09-30»).
    public static func dayString(_ date: Date = Date()) -> String {
        formatter("yyyy-MM-dd").string(from: date)
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateFormat = format
        return formatter
    }
}
