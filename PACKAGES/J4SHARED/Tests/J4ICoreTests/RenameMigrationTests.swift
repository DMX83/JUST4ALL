import XCTest
@testable import J4ICore

/// Migración del renombrado JUST4INDEX → JUST4DESK: copia de preferencias y datos locales.
/// (Regresión del 25-sep: la app debe adoptar la configuración antigua sin pasar por el
/// asistente de primer arranque, y sin tocar los datos originales.)
final class RenameMigrationTests: XCTestCase {
    private var tempDir: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("j4d-rename-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        suiteName = "j4d-rename-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testCopiesLegacyPreferencesWithoutOverwriting() throws {
        defaults.set("preferencia-nueva", forKey: "just4desk.filing.sourcePath")

        let result = RenameMigration.migrate(
            defaults: defaults,
            legacyValues: [
                "just4index.filing.sourcePath": "preferencia-vieja",
                "just4index.filing.rootPath": "/Users/alguien/JUST4INDEX",
                "just4index.ai.dailyLimit": 400,
                "otraClave": "ignorada"
            ],
            legacyFolder: nil,
            currentFolder: nil,
            fileManager: .default
        )

        XCTAssertTrue(result.migrated)
        XCTAssertFalse(result.failed)
        XCTAssertEqual(defaults.string(forKey: "just4desk.filing.rootPath"), "/Users/alguien/JUST4INDEX")
        XCTAssertEqual(defaults.integer(forKey: "just4desk.ai.dailyLimit"), 400)
        XCTAssertEqual(
            defaults.string(forKey: "just4desk.filing.sourcePath"),
            "preferencia-nueva",
            "un valor nuevo existente no debe pisarse con el antiguo"
        )
        XCTAssertNil(defaults.object(forKey: "just4desk.otraClave"), "solo se migran claves just4index.*")
    }

    func testCopiesDataFolderAndKeepsTheOriginal() throws {
        let legacy = tempDir.appendingPathComponent("JUST4INDEX", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try "conocimiento".write(to: legacy.appendingPathComponent("knowledge.json"), atomically: true, encoding: .utf8)

        let current = tempDir.appendingPathComponent("JUST4DESK", isDirectory: true)
        let result = RenameMigration.migrate(
            defaults: defaults,
            legacyValues: [:],
            legacyFolder: legacy,
            currentFolder: current,
            fileManager: .default
        )

        XCTAssertTrue(result.migrated)
        XCTAssertFalse(result.failed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: current.appendingPathComponent("knowledge.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.appendingPathComponent("knowledge.json").path), "el original se conserva como respaldo")
    }

    func testIsIdempotentWhenDestinationAlreadyExists() throws {
        let legacy = tempDir.appendingPathComponent("JUST4INDEX", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        let current = tempDir.appendingPathComponent("JUST4DESK", isDirectory: true)
        try FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)

        let result = RenameMigration.migrate(
            defaults: defaults,
            legacyValues: ["just4index.filing.rootPath": "/x"],
            legacyFolder: legacy,
            currentFolder: current,
            fileManager: .default
        )

        XCTAssertFalse(result.failed, "si el destino ya existe no se toca nada")
    }
}
