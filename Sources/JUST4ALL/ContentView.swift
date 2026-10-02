import SwiftUI
import AppKit

struct ContentView: View {
    @State private var statusMessage = "Selecciona una app"
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var selectedApp: SubApp? = SubAppsCatalog.items.first
    @State private var showInstallSheet = false
    @State private var installingApp: SubApp? = nil
    @StateObject private var downloadManager = DownloadManager()
    @StateObject private var releaseStore = ReleaseStore()
    /// Recibe lo que se elija desde el menú del Dock o de la barra de menús.
    @ObservedObject private var hubBridge = HubBridge.shared

    private let apps = SubAppsCatalog.items
    private let historyStore = SubAppHistoryStore()

    var body: some View {
        ZStack {
            HubBackground()

            VStack(spacing: 18) {
                header

                HStack(alignment: .top, spacing: 18) {
                    ScrollView {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: HubDesign.cardMinWidth), spacing: 14)],
                            spacing: 14
                        ) {
                            ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                                SubAppCard(
                                    app: app,
                                    state: state(for: app),
                                    isSelected: selectedApp == app,
                                    shortcutHint: "⌘\(index + 1)"
                                ) {
                                    selectedApp = app
                                    statusMessage = "Seleccionada: \(app.name)"
                                }
                                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                            }
                        }
                        .padding(.bottom, 6)
                    }

                    detailPanel
                        .frame(width: HubDesign.detailWidth)
                }

                footer
            }
            .padding(22)
            .frame(minWidth: 940, minHeight: 620)
        }
        .alert("No se pudo abrir", isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .sheet(isPresented: $showInstallSheet) {
            installSheet
        }
        .task {
            await releaseStore.refresh()
        }
        .onReceive(hubBridge.$pendingApp) { app in
            // `@Published` emite el valor actual al suscribirse: el `guard` evita actuar de más.
            guard app != nil else { return }
            applyBridgeRequest()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("JUST4ALL")
                    .font(HubDesign.wordmark)
                Text(summaryLine)
                    .font(HubDesign.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            HubStatusPill(text: statusMessage)
        }
    }

    /// «6 apps · 1 instalada · 5 copias locales»: el resumen, de un vistazo.
    private var summaryLine: String {
        let states = apps.map { state(for: $0) }
        let installed = states.filter(\.isInstalledInApplications).count
        let localCopies = states.filter { if case .localCopy = $0 { return true } else { return false } }.count
        let updates = states.filter { if case .updateAvailable = $0 { return true } else { return false } }.count

        var parts = ["\(apps.count) apps", "\(installed) \(installed == 1 ? "instalada" : "instaladas")"]
        if localCopies > 0 {
            parts.append("\(localCopies) sin instalar (copia en el Mac)")
        }
        if updates > 0 {
            parts.append("\(updates) con actualización")
        }
        return parts.joined(separator: " · ")
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Label("Clic derecho en el icono del Dock para levantar una app", systemImage: "cursorarrow.click.2")
            Spacer(minLength: 12)
            Text("⌘1–⌘6 elige · ⌘↩ abre")
        }
        .font(HubDesign.caption)
        .foregroundStyle(.tertiary)
    }

    private var detailPanel: some View {
        Group {
            if let app = selectedApp {
                VStack(alignment: .leading, spacing: 0) {
                    ScrollView {
                        detailContent(for: app)
                            .padding(18)
                    }

                    Divider()

                    detailActions(for: app)
                        .padding(18)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 26))
                        .foregroundStyle(.tertiary)
                    Text("Elige una app de la izquierda")
                        .font(HubDesign.body)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.background)
                .shadow(color: .black.opacity(0.10), radius: 14, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.primary.opacity(0.08))
        )
    }

    private func openApp(_ app: SubApp) {
        // La lógica vive en SubAppLauncher porque la comparten la ventana, el menú del Dock
        // y la barra de menús. Aquí sólo se traduce el resultado a mensajes de estado.
        switch SubAppLauncher.open(app, fallbackToHub: false) {
        case .opened:
            historyStore.record(.opened, for: app)
            statusMessage = "Abierta: \(app.name)"
        case .openedFromSource:
            historyStore.record(.opened, for: app)
            statusMessage = "Abierta (dev): \(app.name)"
        case .needsInstall:
            openDownload(app)
        }
    }

    private func openDownload(_ app: SubApp) {
        installingApp = app
        showInstallSheet = true

        Task { @MainActor in
            // If a previous download exists, just open the DMG.
            if let downloaded = alreadyDownloadedFileURL(for: app, fileName: currentDownloadFileName(for: app)) {
                NSWorkspace.shared.open(downloaded)
                historyStore.record(.downloaded, for: app, version: currentDownloadVersionString(for: app))
                statusMessage = "DMG listo"
                return
            }

            guard let download = currentDownloadAsset(for: app) else {
                alertMessage = "No se encontro descarga para \(app.name)."
                showAlert = true
                statusMessage = "Sin descarga"
                return
            }

            statusMessage = "Descargando \(app.name)..."
            if let fileURL = await downloadManager.downloadToDownloadsFolder(
                from: download.url,
                fileName: download.fileName,
                appName: app.name,
                expectedSha256: download.sha256
            ) {
                historyStore.record(.downloaded, for: app, version: download.version)
                statusMessage = "Descarga lista"
                NSWorkspace.shared.open(fileURL)
            } else {
                alertMessage = "No se pudo descargar/verificar \(app.name)."
                showAlert = true
                statusMessage = "Error al descargar"
            }
        }
    }

    /// Captura de la app. Sólo se llama cuando la imagen existe de verdad.
    private func screenshotCard(_ name: String) -> some View {
        Group {
            if let image = loadImage(named: name) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: 186, height: 112)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.primary.opacity(0.10))
        )
    }

    private func loadImage(named name: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: nil) else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    private func isInstalled(_ app: SubApp) -> Bool {
        SubAppLauncher.isInstalled(app)
    }

    /// Subapp elegida desde el menú del Dock o de la barra de menús: se selecciona y, si aún
    /// no está instalada, se abre su descarga (el menú no puede hacer nada de eso solo).
    private func applyBridgeRequest() {
        guard let app = hubBridge.takePendingApp() else { return }
        selectedApp = app
        if isInstalled(app) {
            statusMessage = "Elegida en el menú: \(app.name)"
        } else {
            statusMessage = "Sin instalar: \(app.name)"
            openDownload(app)
        }
    }

    private func detailContent(for app: SubApp) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                IconTile(symbol: app.systemIcon, accent: app.accent, size: 52)
                VStack(alignment: .leading, spacing: 5) {
                    Text(app.name)
                        .font(HubDesign.title)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(app.subtitle)
                        .font(HubDesign.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    StateBadge(state: state(for: app))
                }
                Spacer(minLength: 0)
            }

            if let logo = loadImage(named: app.logoName) {
                Image(nsImage: logo)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 90)
            }

            VStack(alignment: .leading, spacing: 7) {
                FactRow(label: "En este Mac", value: installedText(for: app), accent: state(for: app).isInstalledInApplications ? .primary : .secondary)
                FactRow(label: "Publicada", value: publishedText(for: app))
                FactRow(label: "Última vez", value: lastActivityText(for: app))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.quaternary.opacity(0.4))
            )

            DetailSection(title: "Descripción", symbol: "text.alignleft") {
                Text(app.description)
                    .font(HubDesign.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !app.changelog.isEmpty {
                DetailSection(title: "Novedades", symbol: "sparkles") {
                    bullets(app.changelog)
                }
            }

            if !app.requirements.isEmpty {
                DetailSection(title: "Requisitos", symbol: "checklist") {
                    bullets(app.requirements)
                }
            }

            let screenshots = existingScreenshots(for: app)
            if !screenshots.isEmpty {
                DetailSection(title: "Capturas", symbol: "photo.on.rectangle") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(screenshots, id: \.self) { name in
                                screenshotCard(name)
                            }
                        }
                    }
                    .frame(height: 118)
                }
            }

            if !app.links.isEmpty {
                DetailSection(title: "Enlaces", symbol: "link") {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(app.links) { link in
                            if let url = URL(string: link.url) {
                                Link(destination: url) {
                                    Label(link.label, systemImage: "arrow.up.right.square")
                                        .font(HubDesign.body)
                                }
                                .buttonStyle(.link)
                            }
                        }
                    }
                }
            }

            historySection(for: app)
        }
    }

    private func detailActions(for app: SubApp) -> some View {
        let appState = state(for: app)
        let hasDownload = latestReleaseAsset(for: app) != nil

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    openApp(app)
                } label: {
                    Label("Abrir", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!appState.canOpen)
                .keyboardShortcut(.return, modifiers: .command)

                Button {
                    openDownload(app)
                } label: {
                    Label(downloadButtonLabel(for: appState), systemImage: "arrow.down.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(!hasDownload)
            }

            if hasDownload {
                Text("Se descarga desde GitHub Releases y se comprueba su SHA-256 antes de abrirla.")
                    .font(HubDesign.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 8) {
                    Text("Todavía no hay descarga publicada para esta app.")
                        .font(HubDesign.caption)
                        .foregroundStyle(.tertiary)
                    Button("Refrescar") {
                        Task { await releaseStore.refresh() }
                    }
                    .buttonStyle(.link)
                    .font(HubDesign.caption)
                }
            }
        }
    }

    private func historySection(for app: SubApp) -> some View {
        let entries = historyStore.history(for: app)
        return DetailSection(title: "Historial", symbol: "clock.arrow.circlepath") {
            if entries.isEmpty {
                Text("Todavía no has abierto ni descargado esta app.")
                    .font(HubDesign.body)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(entries) { entry in
                        HStack(spacing: 8) {
                            Text(historyLabel(for: entry))
                            Text("v\(entry.version)")
                                .font(HubDesign.mono)
                                .foregroundStyle(.tertiary)
                            Spacer(minLength: 0)
                            Text(formattedHistoryDate(entry.date))
                        }
                        .font(HubDesign.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func alreadyDownloadedFileURL(for app: SubApp, fileName: String) -> URL? {
        guard let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dmgUrl = downloads.appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: dmgUrl.path) ? dmgUrl : nil
    }

    private func latestReleaseAsset(for app: SubApp) -> SubAppReleaseAsset? {
        releaseStore.assetsByPrefix[app.assetPrefix]
    }

    // MARK: - Estado y datos de cada app

    /// El estado que se enseña: lo instalado en /Applications, la copia que haya por el Mac y
    /// lo publicado en GitHub.
    private func state(for app: SubApp) -> SubAppState {
        SubAppState.resolve(
            installedVersion: SubAppLauncher.installedVersion(of: app),
            localVersion: SubAppLauncher.knownVersion(of: app),
            publishedVersion: latestReleaseAsset(for: app)?.version.description
        )
    }

    private func installedText(for app: SubApp) -> String {
        if let installed = SubAppLauncher.installedVersion(of: app) {
            return installed
        }
        if let local = SubAppLauncher.knownVersion(of: app) {
            return "\(local) (copia local)"
        }
        return "No está en este Mac"
    }

    private func publishedText(for app: SubApp) -> String {
        if let latest = latestReleaseAsset(for: app) {
            return latest.version.description
        }
        if releaseStore.lastError != nil {
            return "Sin datos (revisa la conexión)"
        }
        return "Sin publicar"
    }

    private func lastActivityText(for app: SubApp) -> String {
        guard let last = historyStore.history(for: app).first else { return "—" }
        return "\(historyLabel(for: last)) · \(formattedHistoryDate(last.date))"
    }

    /// Texto del botón de descarga: si hay algo más nuevo, dice a qué versión se salta.
    private func downloadButtonLabel(for state: SubAppState) -> String {
        if case .updateAvailable(let installed, let published) = state {
            return "Actualizar \(installed) → \(published)"
        }
        return "Descargar"
    }

    private func bullets(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("•")
                        .foregroundStyle(.tertiary)
                    Text(item)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(HubDesign.body)
        .foregroundStyle(.secondary)
    }

    /// Sólo las capturas que existen de verdad: antes se pintaban recuadros «Screenshot».
    private func existingScreenshots(for app: SubApp) -> [String] {
        app.screenshots.filter { loadImage(named: $0) != nil }
    }

    private struct DownloadAsset {
        let url: URL
        let fileName: String
        let version: String
        let sha256: String?
    }

    private func currentDownloadAsset(for app: SubApp) -> DownloadAsset? {
        if let latest = latestReleaseAsset(for: app) {
            return DownloadAsset(
                url: latest.downloadURL,
                fileName: latest.fileName,
                version: latest.version.description,
                sha256: latest.sha256
            )
        }
        return nil
    }

    private func currentDownloadFileName(for app: SubApp) -> String {
        currentDownloadAsset(for: app)?.fileName ?? SubAppsCatalog.pinnedFileName(for: app)
    }

    private func currentDownloadVersionString(for app: SubApp) -> String {
        currentDownloadAsset(for: app)?.version ?? app.version
    }

    private func historyLabel(for entry: SubAppHistoryEntry) -> String {
        switch entry.action {
        case .opened:
            return "Abierta"
        case .downloaded:
            return "Descargada"
        }
    }

    private func formattedHistoryDate(_ date: Date) -> String {
        ContentView.historyDateFormatter.string(from: date)
    }

    private static let historyDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private var installSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(installingApp?.name ?? "Instalacion")
                .font(.custom("Avenir Next", size: 20).weight(.bold))

            switch downloadManager.state {
            case .downloading(let appName, let progress, let bytesWritten, let bytesExpected):
                Text("Descargando \(appName)...")
                    .font(.custom("Avenir Next", size: 12).weight(.semibold))
                if let progress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                    Text("\(Int(progress * 100))%")
                        .font(.custom("Avenir Next", size: 11))
                        .foregroundColor(.secondary)
                } else if let bytesExpected, bytesExpected > 0 {
                    let p = Double(bytesWritten) / Double(bytesExpected)
                    ProgressView(value: p)
                        .progressViewStyle(.linear)
                } else {
                    ProgressView()
                        .progressViewStyle(.circular)
                }
            case .failed(let message):
                VStack(alignment: .leading, spacing: 8) {
                    Text(message)
                        .font(.custom("Avenir Next", size: 12))
                        .foregroundColor(.secondary)
                    if let app = installingApp {
                        Button("Reintentar") { openDownload(app) }
                            .buttonStyle(.bordered)
                    }
                }
            default:
                EmptyView()
            }

            Text("Pasos de instalacion")
                .font(.custom("Avenir Next", size: 12).weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                ForEach(installSteps(for: installingApp), id: \.self) { step in
                    Text("• \(step)")
                        .font(.custom("Avenir Next", size: 12))
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 12) {
                Button("Abrir Descargas") {
                    openDownloadsFolder()
                }
                .buttonStyle(.bordered)

                Button("Abrir DMG") {
                    openDownloadedDmg()
                }
                .buttonStyle(.borderedProminent)
                .disabled({
                    guard let app = installingApp else { return true }
                    return alreadyDownloadedFileURL(for: app, fileName: currentDownloadFileName(for: app)) == nil
                }())
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 420, height: 260)
    }

    private func installSteps(for app: SubApp?) -> [String] {
        guard let app else {
            return [
                "Descarga el DMG.",
                "Abre el DMG.",
                "Arrastra la app a Applications.",
                "Vuelve a JUST4ALL y presiona Abrir."
            ]
        }
        let fileName = currentDownloadFileName(for: app)
        return [
            "Descarga \(fileName).",
            "Abre el DMG.",
            "Arrastra \(app.name) a Applications.",
            "Vuelve a JUST4ALL y presiona Abrir."
        ]
    }

    private func openDownloadsFolder() {
        if let url = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            NSWorkspace.shared.open(url)
        }
    }

    private func openDownloadedDmg() {
        guard let app = installingApp,
              let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            openDownloadsFolder()
            return
        }

        let dmgUrl = downloads.appendingPathComponent(currentDownloadFileName(for: app))
        if FileManager.default.fileExists(atPath: dmgUrl.path) {
            NSWorkspace.shared.open(dmgUrl)
        } else {
            openDownloadsFolder()
        }
    }
}
