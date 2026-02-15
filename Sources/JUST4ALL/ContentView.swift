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

    private let apps = SubAppsCatalog.items
    private let historyStore = SubAppHistoryStore()

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        ZStack {
            background

            VStack(spacing: 24) {
                header
                HStack(alignment: .top, spacing: 20) {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(apps) { app in
                            SubAppCard(
                                app: app,
                                isSelected: selectedApp == app,
                                isInstalled: isInstalled(app)
                            ) {
                                selectedApp = app
                                statusMessage = "Seleccionada: \(app.name)"
                            }
                        }
                    }
                    detailPanel
                        .frame(width: 360)
                }
                footer
            }
            .padding(30)
            .frame(minWidth: 980, minHeight: 600)
        }
        .alert("No se pudo abrir", isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .sheet(isPresented: $showInstallSheet) {
            installSheet
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text("JUST4ALL")
                    .font(.custom("Avenir Next", size: 30).weight(.bold))
                Text("Selecciona una subapp para ver detalles")
                    .font(.custom("Avenir Next", size: 13))
                    .foregroundColor(.secondary)
            }
            Spacer()
            statusPill(text: statusMessage)
        }
    }

    private var footer: some View {
        HStack {
            Text("Apps instaladas en macOS")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    private var detailPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let app = selectedApp {
                ScrollView {
                    detailContent(for: app)
                }

                Divider()
                detailActions(for: app)
            } else {
                Text("Selecciona una app para ver detalles")
                    .font(.custom("Avenir Next", size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .padding(18)
        .frame(maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.9))
                .shadow(color: Color.black.opacity(0.08), radius: 14, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.35), lineWidth: 1)
        )
    }

    private func openApp(_ app: SubApp) {
        guard let url = appURL(for: app) else {
            openDownload(app)
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
            if let error = error {
                let fallbackOpened = NSWorkspace.shared.open(url)
                if !fallbackOpened {
                    alertMessage = error.localizedDescription
                    showAlert = true
                    statusMessage = "Error al abrir"
                } else {
                    historyStore.record(.opened, for: app)
                    statusMessage = "Abierta: \(app.name)"
                }
            } else {
                historyStore.record(.opened, for: app)
                statusMessage = "Abierta: \(app.name)"
            }
        }

        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleId) != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleId).isEmpty {
                    _ = NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private func openDownload(_ app: SubApp) {
        installingApp = app
        showInstallSheet = true

        Task { @MainActor in
            // If a previous download exists, just open the DMG.
            if let downloaded = alreadyDownloadedFileURL(for: app) {
                NSWorkspace.shared.open(downloaded)
                historyStore.record(.downloaded, for: app)
                statusMessage = "DMG listo"
                return
            }

            guard let url = URL(string: app.downloadUrl), url.scheme != nil else {
                alertMessage = "No se encontro link de descarga para \(app.name)."
                showAlert = true
                statusMessage = "Sin descarga"
                return
            }

            statusMessage = "Descargando \(app.name)..."
            if let fileURL = await downloadManager.downloadToDownloadsFolder(from: url, fileName: app.downloadFileName, appName: app.name) {
                historyStore.record(.downloaded, for: app)
                statusMessage = "Descarga lista"
                NSWorkspace.shared.open(fileURL)
            } else {
                alertMessage = "No se pudo descargar \(app.name). Si el repo es privado, GitHub bloquea descargas desde apps sin login."
                showAlert = true
                statusMessage = "Error al descargar"
            }
        }
    }

    private func detailSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.custom("Avenir Next", size: 12).weight(.semibold))
            content()
        }
    }

    private func logoView(for app: SubApp) -> some View {
        Group {
            if let image = loadImage(named: app.logoName) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 76)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(app.accent.opacity(0.15))
                    Text(app.name)
                        .font(.custom("Avenir Next", size: 12).weight(.bold))
                        .foregroundColor(app.accent)
                }
                .frame(height: 76)
            }
        }
    }

    private func screenshotCard(_ name: String) -> some View {
        Group {
            if let image = loadImage(named: name) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(NSColor.windowBackgroundColor))
                    Text("Screenshot")
                        .font(.custom("Avenir Next", size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(width: 170, height: 104)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.94, green: 0.94, blue: 0.92), Color(red: 0.90, green: 0.94, blue: 0.98)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color(red: 0.15, green: 0.46, blue: 0.82).opacity(0.08))
                .frame(width: 420, height: 420)
                .offset(x: -280, y: -220)

            Circle()
                .fill(Color(red: 0.18, green: 0.67, blue: 0.47).opacity(0.08))
                .frame(width: 360, height: 360)
                .offset(x: 320, y: 260)
        }
    }

    private func statusPill(text: String) -> some View {
        Text(text)
            .font(.custom("Avenir Next", size: 11).weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.6))
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.6), lineWidth: 1)
            )
            .foregroundColor(.secondary)
    }

    private func loadImage(named name: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: nil) else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    private func isInstalled(_ app: SubApp) -> Bool {
        appURL(for: app) != nil
    }

    private func appURL(for app: SubApp) -> URL? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleId) {
            return url
        }

        let applicationsURL = URL(fileURLWithPath: "/Applications/\(app.name).app")
        if FileManager.default.fileExists(atPath: applicationsURL.path) {
            return applicationsURL
        }

        let userApplicationsPath = ("~/Applications/\(app.name).app" as NSString).expandingTildeInPath
        let userApplicationsURL = URL(fileURLWithPath: userApplicationsPath)
        if FileManager.default.fileExists(atPath: userApplicationsURL.path) {
            return userApplicationsURL
        }

        return nil
    }

    private func detailContent(for app: SubApp) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(app.name)
                    .font(.custom("Avenir Next", size: 18).weight(.bold))
                Text(app.subtitle)
                    .font(.custom("Avenir Next", size: 12))
                    .foregroundColor(.secondary)
            }

            logoView(for: app)

            Divider()

            detailSection(title: "Descripcion") {
                Text(app.description)
                    .font(.custom("Avenir Next", size: 12))
                    .foregroundColor(.secondary)
            }

            detailSection(title: "Version") {
                Text(app.version)
                    .font(.custom("Avenir Next", size: 12))
                    .foregroundColor(.secondary)
            }

            detailSection(title: "Changelog") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(app.changelog, id: \.self) { item in
                        Text("• \(item)")
                            .font(.custom("Avenir Next", size: 12))
                            .foregroundColor(.secondary)
                    }
                }
            }

            historySection(for: app)

            detailSection(title: "Requisitos") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(app.requirements, id: \.self) { item in
                        Text("• \(item)")
                            .font(.custom("Avenir Next", size: 12))
                            .foregroundColor(.secondary)
                    }
                }
            }

            linksSection(for: app)

            detailSection(title: "Screenshots") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(app.screenshots, id: \.self) { name in
                            screenshotCard(name)
                        }
                    }
                }
                .frame(height: 120)
            }
        }
    }

    private func detailActions(for app: SubApp) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(isInstalled(app) ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(isInstalled(app) ? "Instalada" : "No instalada")
                    .font(.custom("Avenir Next", size: 12))
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 10) {
                Button("Abrir \(app.name)") {
                    openApp(app)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isInstalled(app))

                Button("Descargar \(app.name)") {
                    openDownload(app)
                }
                .buttonStyle(.bordered)
            }

            if isBundledDownloadAvailable(for: app) {
                Text("Instalacion local sin internet")
                    .font(.custom("Avenir Next", size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func linksSection(for app: SubApp) -> some View {
        detailSection(title: "Links") {
            VStack(alignment: .leading, spacing: 6) {
                if app.links.isEmpty {
                    Text("Links no disponibles")
                        .font(.custom("Avenir Next", size: 12))
                        .foregroundColor(.secondary)
                } else {
                    ForEach(app.links) { link in
                        if let url = URL(string: link.url) {
                            Link(link.label, destination: url)
                                .font(.custom("Avenir Next", size: 12).weight(.semibold))
                        }
                    }
                }
            }
        }
    }

    private func historySection(for app: SubApp) -> some View {
        detailSection(title: "Historial") {
            let entries = historyStore.history(for: app)
            if entries.isEmpty {
                Text("Sin historial")
                    .font(.custom("Avenir Next", size: 12))
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(entries) { entry in
                        HStack {
                            Text("\(historyLabel(for: entry)) v\(entry.version)")
                            Spacer()
                            Text(formattedHistoryDate(entry.date))
                        }
                        .font(.custom("Avenir Next", size: 11))
                        .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private func isBundledDownloadAvailable(for app: SubApp) -> Bool {
        // DMGs are not bundled anymore.
        return false
    }

    private func alreadyDownloadedFileURL(for app: SubApp) -> URL? {
        guard let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dmgUrl = downloads.appendingPathComponent(app.downloadFileName)
        return FileManager.default.fileExists(atPath: dmgUrl.path) ? dmgUrl : nil
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
            case .downloading(let appName, let progress):
                Text("Descargando \(appName)...")
                    .font(.custom("Avenir Next", size: 12).weight(.semibold))
                if let progress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                } else {
                    ProgressView()
                        .progressViewStyle(.circular)
                }
            case .failed(let message):
                Text(message)
                    .font(.custom("Avenir Next", size: 12))
                    .foregroundColor(.secondary)
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
                    return alreadyDownloadedFileURL(for: app) == nil
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
        return [
            "Descarga \(app.downloadFileName).",
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

        let dmgUrl = downloads.appendingPathComponent(app.downloadFileName)
        if FileManager.default.fileExists(atPath: dmgUrl.path) {
            NSWorkspace.shared.open(dmgUrl)
        } else {
            openDownloadsFolder()
        }
    }
}
