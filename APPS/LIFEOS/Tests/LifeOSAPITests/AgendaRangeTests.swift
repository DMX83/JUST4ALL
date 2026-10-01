import XCTest

import LifeOSAPI

/// Los intervalos de la agenda.
///
/// Es aritmética de fechas, de las que se equivocan en silencio: si el final de la
/// semana queda un día corto, la agenda «pierde» el domingo y nadie se entera.
final class AgendaRangeTests: XCTestCase {
    /// Calendario fijo: semana que empieza el lunes (como en español), zona UTC
    /// para que las horas no dependan de dónde se ejecute la prueba.
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "es_ES")
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return calendar.date(from: components)!
    }

    func testDayIsHalfOpenAtMidnight() {
        let bounds = AgendaRange.day(date(2026, 9, 30, 14), calendar: calendar)

        XCTAssertEqual(bounds.start, date(2026, 9, 30, 0))
        XCTAssertEqual(bounds.end, date(2026, 10, 1, 0), "El final es exclusivo: el día siguiente a las 00:00")
    }

    func testWeekStartsOnMondayAndCoversSevenDays() {
        // Miércoles 30-sep-2026.
        let bounds = AgendaRange.week(containing: date(2026, 9, 30, 9), calendar: calendar)

        XCTAssertEqual(bounds.start, date(2026, 9, 28), "La semana empieza el lunes 28")
        XCTAssertEqual(bounds.end, date(2026, 10, 5), "Y acaba el lunes siguiente a las 00:00")
    }

    func testWeekOfAMondayIsItself() {
        let bounds = AgendaRange.week(containing: date(2026, 9, 28, 8), calendar: calendar)
        XCTAssertEqual(bounds.start, date(2026, 9, 28))
    }

    func testWeekOfASundayBelongsToTheWeekThatOpened() {
        let bounds = AgendaRange.week(containing: date(2026, 10, 4, 23), calendar: calendar)
        XCTAssertEqual(bounds.start, date(2026, 9, 28), "El domingo cierra la semana del lunes anterior")
        XCTAssertEqual(bounds.end, date(2026, 10, 5))
    }

    func testDaysOfTheWeekAreSevenAndInOrder() {
        let days = AgendaRange.days(ofWeekContaining: date(2026, 9, 30), calendar: calendar)

        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.first, date(2026, 9, 28))
        XCTAssertEqual(days.last, date(2026, 10, 4))
        XCTAssertEqual(days, days.sorted())
    }

    func testSteppingKeepsTheTimeOfDayOut() {
        let stepped = AgendaRange.day(date(2026, 9, 30, 23), offset: 1, calendar: calendar)
        XCTAssertEqual(calendar.startOfDay(for: stepped), date(2026, 10, 1))
        XCTAssertEqual(calendar.component(.hour, from: stepped), 23, "Se conserva la hora")
    }
}
