import XCTest
@testable import J4IAI

final class AIControlCenterTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var center: AIControlCenter!

    override func setUpWithError() throws {
        suiteName = "j4i-ai-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        center = AIControlCenter(defaults: defaults)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testCapDiarioBloqueaYCuentaLlamadas() {
        XCTAssertTrue(center.canUseAI(), "por defecto, habilitada")
        center.dailyLimit = 2

        center.registerCall()
        center.registerCall()
        XCTAssertFalse(center.canUseAI(), "cap alcanzado → no se puede llamar")
        let usage = center.usage()
        XCTAssertEqual(usage.callsToday, 2)
        XCTAssertEqual(usage.callsTotal, 2)
        XCTAssertTrue(usage.limitReached)
    }

    func testInterruptorDesactivaSinBorrarContadores() {
        center.registerCall()
        center.isEnabled = false
        XCTAssertFalse(center.canUseAI())
        XCTAssertEqual(center.usage().callsTotal, 1, "el contador no se pierde al apagar")

        center.isEnabled = true
        XCTAssertTrue(center.canUseAI())
    }

    func testTokensAcumulanYReinicianPorDia() {
        center.registerCall()
        center.registerTokens(2400)
        center.registerTokens(1800)
        XCTAssertEqual(center.usage().tokensToday, 4200)
        XCTAssertEqual(center.usage().tokensTotal, 4200)

        // Simula que la última actividad fue «ayer»: los tokens de hoy se reinician, el total no.
        defaults.set("2000-01-01", forKey: AIControlCenter.Keys.callsDate)
        let usage = center.usage()
        XCTAssertEqual(usage.tokensToday, 0, "nuevo día → tokens de hoy a cero")
        XCTAssertEqual(usage.tokensTotal, 4200, "el total de tokens se conserva")
    }

    func testRolloverDiarioReiniciaHoyPeroNoElTotal() {
        center.registerCall()
        XCTAssertEqual(center.usage().callsToday, 1)

        // Simula que la última llamada fue «ayer».
        defaults.set("2000-01-01", forKey: AIControlCenter.Keys.callsDate)
        let usage = center.usage()
        XCTAssertEqual(usage.callsToday, 0, "nuevo día → contador diario a cero")
        XCTAssertEqual(usage.callsTotal, 1, "el total acumulado se conserva")

        center.registerCall()
        XCTAssertEqual(center.usage().callsToday, 1)
        XCTAssertEqual(center.usage().callsTotal, 2)
    }
}
