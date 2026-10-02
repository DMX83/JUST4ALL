import XCTest
@testable import JUST4ALL

/// El estado de una subapp es lo que decide qué pone la tarjeta y si el botón abre, descarga
/// o actualiza. Estas pruebas fijan la regla, incluida la que hacía que el hub dijera
/// «6 instaladas» por culpa de LaunchServices.
final class SubAppStateTests: XCTestCase {
    func testInstalledAndUpToDateIsInstalled() {
        XCTAssertEqual(
            SubAppState.resolve(installedVersion: "2.3.15", localVersion: nil, publishedVersion: "2.3.15"),
            .installed(version: "2.3.15")
        )
    }

    func testInstalledWithoutPublishedVersionIsInstalled() {
        XCTAssertEqual(
            SubAppState.resolve(installedVersion: "2.3.15", localVersion: nil, publishedVersion: nil),
            .installed(version: "2.3.15")
        )
    }

    func testNewerPublishedVersionOffersUpdate() {
        XCTAssertEqual(
            SubAppState.resolve(installedVersion: "0.1.0", localVersion: nil, publishedVersion: "2.3.15"),
            .updateAvailable(installed: "0.1.0", published: "2.3.15")
        )
    }

    /// El caso real: la app no está en /Applications pero su bundle anda por el repo.
    func testBundleOutsideApplicationsIsACopyNotAnInstallation() {
        let state = SubAppState.resolve(installedVersion: nil, localVersion: "0.1.0", publishedVersion: "0.1.0")

        XCTAssertEqual(state, .localCopy(version: "0.1.0"))
        XCTAssertFalse(state.isInstalledInApplications)
        XCTAssertTrue(state.canOpen, "Una copia local se puede abrir")
        XCTAssertEqual(state.compactLabel, "Copia local")
    }

    func testNothingAnywhereIsNotInstalled() {
        let state = SubAppState.resolve(installedVersion: nil, localVersion: nil, publishedVersion: "2.3.15")

        XCTAssertEqual(state, .notInstalled)
        XCTAssertFalse(state.canOpen)
        XCTAssertFalse(state.isInstalledInApplications)
    }

    /// Si la versión instalada no se puede leer como SemVer, no se inventa una actualización.
    func testUnreadableInstalledVersionStaysInstalled() {
        XCTAssertEqual(
            SubAppState.resolve(installedVersion: "lo que sea", localVersion: nil, publishedVersion: "2.3.15"),
            .installed(version: "lo que sea")
        )
    }

    func testInstalledWinsOverTheLocalCopy() {
        let state = SubAppState.resolve(installedVersion: "2.3.15", localVersion: "0.1.0", publishedVersion: nil)

        XCTAssertEqual(state, .installed(version: "2.3.15"))
        XCTAssertTrue(state.isInstalledInApplications)
    }

    // MARK: - Qué cuenta como «instalada»

    func testPathsInsideApplicationsFoldersCount() {
        XCTAssertTrue(SubAppLauncher.isInsideApplications(path: "/Applications/JUST4DESK.app", homeDirectory: "/Users/prueba"))
        XCTAssertTrue(SubAppLauncher.isInsideApplications(path: "/Users/prueba/Applications/JUST4DESK.app", homeDirectory: "/Users/prueba"))
    }

    func testPathsOutsideApplicationsFoldersDoNotCount() {
        // Regresión: estas rutas las conoce LaunchServices y antes se daban por «instalada».
        XCTAssertFalse(SubAppLauncher.isInsideApplications(path: "/Users/prueba/Repos/JUST4ALL/APPS/JUST4PDF/dist/JUST4PDF.app", homeDirectory: "/Users/prueba"))
        XCTAssertFalse(SubAppLauncher.isInsideApplications(path: "/Volumes/JUST4FOLDERS/JUST4FOLDERS.app", homeDirectory: "/Users/prueba"))
    }
}
