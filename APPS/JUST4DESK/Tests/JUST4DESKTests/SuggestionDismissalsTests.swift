import XCTest
@testable import JUST4DESK
import J4IFiling

/// G2 — silencios de sugerencias: «Ahora no» oculta 7 días y «Nunca más» para siempre,
/// sin afectar a otras sugerencias.
final class SuggestionDismissalsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var dismissals: SuggestionDismissals!

    override func setUpWithError() throws {
        suiteName = "j4d-suggestion-dismissals-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        dismissals = SuggestionDismissals(defaults: defaults)
    }

    override func tearDownWithError() throws {
        UserDefaults().removePersistentDomain(forName: suiteName)
        defaults = nil
        dismissals = nil
    }

    func testSnoozeHidesForSevenDaysOnly() {
        let now = Date()
        XCTAssertFalse(dismissals.isDismissed(.screenshots, now: now))

        dismissals.snooze(.screenshots, forever: false, now: now)

        XCTAssertTrue(dismissals.isDismissed(.screenshots, now: now.addingTimeInterval(6 * 24 * 3600)))
        XCTAssertFalse(dismissals.isDismissed(.screenshots, now: now.addingTimeInterval(8 * 24 * 3600)))
        XCTAssertFalse(dismissals.isDismissed(.duplicates, now: now), "no afecta a otras sugerencias")
    }

    func testNeverDismissesForever() {
        let now = Date()
        dismissals.snooze(.duplicates, forever: false, now: now)
        dismissals.snooze(.duplicates, forever: true, now: now)

        XCTAssertTrue(dismissals.isDismissed(.duplicates, now: now.addingTimeInterval(365 * 24 * 3600)))
    }

    func testPersistsAcrossInstances() {
        let now = Date()
        dismissals.snooze(.largeForgotten, forever: true, now: now)

        let second = SuggestionDismissals(defaults: defaults)
        XCTAssertTrue(second.isDismissed(.largeForgotten, now: now))
    }
}
