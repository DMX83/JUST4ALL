import XCTest
@testable import J4FOps

final class SemanticQueryExpanderTests: XCTestCase {
    func testTermsParsingNormalizesDedupesAndLimits() throws {
        let content = #"{"terms": ["Poliza", " seguro ", "coche", "COCHE", "", "x"]}"#
        let terms = try DeepSeekQueryExpander.terms(fromContent: content)
        XCTAssertEqual(terms, ["poliza", "seguro", "coche"], "normaliza, deduplica (case-insensitive) y descarta cortos")
    }

    func testTermsErrors() throws {
        XCTAssertThrowsError(try DeepSeekQueryExpander.terms(fromContent: "{}"))
        XCTAssertThrowsError(try DeepSeekQueryExpander.terms(fromContent: "no-json"))
        XCTAssertThrowsError(try DeepSeekQueryExpander.terms(fromContent: #"{"terms": [""]}"#))
    }

    func testExpanderRequiresKey() {
        XCTAssertNil(DeepSeekQueryExpander(apiKey: ""), "sin clave no hay expansor")
        XCTAssertNotNil(DeepSeekQueryExpander(apiKey: "clave"))
    }
}

final class ShortcutStoreTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("j4f-shortcuts-\(UUID().uuidString).json")
    }

    func testDefaultsAndLookup() {
        let store = ShortcutStore(url: tempURL())
        XCTAssertEqual(store.command(keyCode: 96, flags: (false, false, false, false)), "copy")
        XCTAssertEqual(store.command(keyCode: 17, flags: (true, false, false, false)), "newTab")
        XCTAssertNil(store.command(keyCode: 96, flags: (true, false, false, false)), "F5 con ⌘ no es copiar")
    }

    func testOverridePersistsAndResets() {
        let url = tempURL()
        let store = ShortcutStore(url: url)
        store.set(ShortcutBinding(command: "copy", keyCode: 99, opt: true))

        XCTAssertEqual(store.command(keyCode: 99, flags: (false, true, false, false)), "copy")
        XCTAssertNil(store.command(keyCode: 96, flags: (false, false, false, false)), "el valor por defecto queda reemplazado")

        let reopened = ShortcutStore(url: url)
        XCTAssertEqual(reopened.command(keyCode: 99, flags: (false, true, false, false)), "copy", "persiste entre instancias")

        reopened.resetAll()
        XCTAssertEqual(reopened.command(keyCode: 96, flags: (false, false, false, false)), "copy", "reset vuelve a los defaults")
    }

    func testDisplayString() {
        let binding = ShortcutBinding(command: "duplicateTab", keyCode: 17, cmd: true, opt: true)
        XCTAssertEqual(binding.displayString, "⌥⌘T")
        XCTAssertEqual(ShortcutBinding(command: "copy", keyCode: 96).displayString, "F5")
    }
}
