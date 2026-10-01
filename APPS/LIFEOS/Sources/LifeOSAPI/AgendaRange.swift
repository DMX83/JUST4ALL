import Foundation

/// Los intervalos que pide la agenda.
///
/// `GET /agenda` exige `start` y `end`, y el servidor cuenta un evento como
/// dentro del intervalo si **se solapa** con él (`ends_at > start` y
/// `starts_at < end`). Es decir: el final es exclusivo, así que un día son
/// `[00:00, 00:00 del día siguiente)` y la semana `[lunes 00:00, lunes siguiente)`.
///
/// Se calcula con el calendario de la persona (en español la semana empieza el
/// lunes), no con uno fijo.
public enum AgendaRange {
    public static func day(_ date: Date, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return (start, end)
    }

    public static func week(containing date: Date, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day)
        // `weekday` es 1 = domingo; se retrocede hasta el primer día de la semana
        // del calendario en uso (lunes por defecto en español).
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        let start = calendar.date(byAdding: .day, value: -offset, to: day) ?? day
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start.addingTimeInterval(604_800)
        return (start, end)
    }

    public static func day(_ date: Date, offset: Int, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: offset, to: date) ?? date
    }

    /// Los días de la semana, para la tira de siete.
    public static func days(ofWeekContaining date: Date, calendar: Calendar = .current) -> [Date] {
        let start = week(containing: date, calendar: calendar).start
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    public static func isToday(_ date: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDateInToday(date)
    }
}
