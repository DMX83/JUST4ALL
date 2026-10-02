import XCTest
import SwiftUI
@testable import JUST4ALL

/// El menú del clic derecho del Dock y el de la barra de menús son «la lista de subapps»:
/// estas pruebas fijan que estén **todas**, en orden y apuntando a la app correcta, que es
/// justo lo que se ve al usarlos.
final class HubMenuTests: XCTestCase {
    private func fakeApp(name: String = "JUST4FAKE", bundleId: String = "com.dmx83.just4fake") -> SubApp {
        SubApp(
            name: name,
            subtitle: "Subapp de mentira para pruebas",
            bundleId: bundleId,
            assetPrefix: name,
            accent: .blue,
            systemIcon: "questionmark",
            description: "",
            requirements: [],
            links: [],
            version: "0.0.0",
            changelog: [],
            logoName: "Assets/\(name)/logo.png",
            screenshots: []
        )
    }

    func testCatalogHasTheSixSubAppsWithUniqueNamesAndIds() {
        let apps = SubAppsCatalog.items
        XCTAssertEqual(apps.count, 6)
        XCTAssertEqual(Set(apps.map(\.name)).count, apps.count)
        XCTAssertEqual(Set(apps.map(\.bundleId)).count, apps.count)
        XCTAssertTrue(apps.allSatisfy { !$0.systemIcon.isEmpty })
    }

    func testDockMenuListsEverySubAppPlusTheWayBackToTheHub() {
        let delegate = AppDelegate()
        guard let menu = delegate.applicationDockMenu(NSApplication.shared) else {
            return XCTFail("El delegado no devolvió el menú del Dock")
        }

        let items = menu.items
        XCTAssertEqual(items.first?.title, AppDelegate.dockMenuHeader)
        XCTAssertFalse(items.first?.isEnabled ?? true, "La cabecera es informativa")

        let subAppItems = items.filter { $0.action == #selector(AppDelegate.openSubApp(_:)) }
        XCTAssertEqual(subAppItems.map(\.title), SubAppsCatalog.items.map(\.name))
        XCTAssertEqual(subAppItems.map(\.tag), Array(SubAppsCatalog.items.indices))
        XCTAssertTrue(subAppItems.allSatisfy { $0.target === delegate })
        XCTAssertTrue(subAppItems.allSatisfy { $0.image != nil })

        XCTAssertTrue(items.contains { $0.title == "Abrir JUST4ALL" })
    }

    /// Lo que hace el menú al pulsar una línea: el `tag` tiene que devolver la subapp exacta.
    func testEveryMenuTagPointsAtItsOwnSubApp() {
        let delegate = AppDelegate()
        let menu = delegate.applicationDockMenu(NSApplication.shared)
        let subAppItems = menu?.items.filter { $0.action == #selector(AppDelegate.openSubApp(_:)) } ?? []

        for item in subAppItems {
            XCTAssertTrue(SubAppsCatalog.items.indices.contains(item.tag))
            XCTAssertEqual(SubAppsCatalog.items[item.tag].name, item.title)
        }
    }

    func testInstalledAppIsFoundInTheUsersApplicationsFolder() throws {
        let app = fakeApp()
        let home = NSTemporaryDirectory() + "j4home-\(UUID().uuidString)"
        let appPath = home + "/Applications/\(app.name).app"
        try FileManager.default.createDirectory(atPath: appPath, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: home) }

        XCTAssertTrue(SubAppLauncher.isInstalled(app, homeDirectory: home))
        XCTAssertEqual(SubAppLauncher.installedAppURL(for: app, homeDirectory: home)?.path, appPath)
    }

    func testAnAppThatIsNotInstalledAnywhereIsNotFound() {
        let app = fakeApp(name: "JUST4NOEXISTE", bundleId: "com.dmx83.just4noexiste")
        let home = NSTemporaryDirectory() + "j4home-vacio-\(UUID().uuidString)"

        XCTAssertFalse(SubAppLauncher.isInstalled(app, homeDirectory: home))
        XCTAssertNil(SubAppLauncher.installedAppURL(for: app, homeDirectory: home))
    }

    func testCandidatePathsCoverBothApplicationsFolders() {
        let app = fakeApp()
        let paths = SubAppLauncher.candidateAppPaths(for: app, homeDirectory: "/tmp/casa")

        XCTAssertEqual(paths, [
            "/Applications/\(app.name).app",
            "/tmp/casa/Applications/\(app.name).app"
        ])
    }

    func testSourceDirectoryIsLookedUpInsideTheGivenRepoRoot() throws {
        let app = fakeApp()
        let root = NSTemporaryDirectory() + "j4repo-\(UUID().uuidString)"
        let appDir = root + "/APPS/\(app.name)"
        try FileManager.default.createDirectory(atPath: appDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: root) }

        let found = SubAppLauncher.sourceDirectory(for: app, repoRoots: [URL(fileURLWithPath: root)])
        XCTAssertEqual(found?.path, appDir)
    }
}
