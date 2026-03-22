import XCTest
@testable import JUST4PICT

final class PictHistoryStoreTests: XCTestCase {
    func testPrependStoresTrimmedPromptSummaryWithoutFullPromptByDefault() {
        let defaults = makeDefaults()
        let store = PictHistoryStore(defaults: defaults)
        let outputURL = URL(fileURLWithPath: "/tmp/out.jpg")
        let longPrompt = String(repeating: "detalle fino ", count: 20)

        let entries = store.prepend(
            current: [],
            inputFileName: "input.jpg",
            outputURL: outputURL,
            preset: .auto,
            format: .jpg,
            aiSuggestedPreset: "Auto",
            aiSuggestedQuality: 0.95,
            aiReason: "mejor resultado",
            aiPrompt: longPrompt,
            storeFullPrompt: false
        )

        XCTAssertEqual(entries.count, 1)
        XCTAssertNil(entries[0].aiPrompt)
        XCTAssertNotNil(entries[0].aiPromptSummary)
        XCTAssertTrue(entries[0].aiPromptSummary?.hasSuffix("…") == true)
        XCTAssertEqual(store.load(), entries)
    }

    func testPrependStoresEffectiveAutoDecisionWhenAvailable() {
        let defaults = makeDefaults()
        let store = PictHistoryStore(defaults: defaults)
        let outputURL = URL(fileURLWithPath: "/tmp/out.png")

        let entries = store.prepend(
            current: [],
            inputFileName: "input.jpg",
            outputURL: outputURL,
            preset: .auto,
            effectiveAutoDecision: "Documento",
            format: .png
        )

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].preset, EnhancementPreset.auto.rawValue)
        XCTAssertEqual(entries[0].effectiveAutoDecision, "Documento")
        XCTAssertEqual(store.load(), entries)
    }

    func testPrependKeepsNewestEntriesFirstAndRespectsMaxEntries() {
        let defaults = makeDefaults()
        let store = PictHistoryStore(defaults: defaults)
        var current: [PictHistoryEntry] = []

        for index in 0..<85 {
            current = store.prepend(
                current: current,
                inputFileName: "input-\(index).jpg",
                outputURL: URL(fileURLWithPath: "/tmp/output-\(index).jpg"),
                preset: .portrait,
                format: .png
            )
        }

        XCTAssertEqual(current.count, 80)
        XCTAssertEqual(current.first?.inputFileName, "input-84.jpg")
        XCTAssertEqual(current.last?.inputFileName, "input-5.jpg")
        XCTAssertEqual(store.load().count, 80)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "JUST4PICTTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
