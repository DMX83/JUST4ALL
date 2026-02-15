import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var selectedType: ConversionType = .audio
    @State private var selectedFormat: ConversionFormat = .m4a
    @State private var selectedFiles: [URL] = []
    @State private var outputDirectory: URL?
    @State private var statusMessage = "Selecciona archivos para convertir."
    @State private var showImporter = false
    @State private var audioBitrate: AudioBitrateOption = .bps192
    @State private var videoResolution: VideoResolutionOption = .original
    @State private var videoFps: VideoFpsOption = .original
    @State private var videoCodec: VideoCodecOption = .h264
    @State private var videoBitrate: VideoBitrateOption = .auto
    @State private var imageQuality: ImageQualityOption = .q85
    @State private var outputNameTemplate = "{name}_{format}"
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var editingItem: QueuedConversion?
    @State private var historyEntries: [ConversionHistoryEntry] = []
    @State private var showHistory = true
    @StateObject private var conversionQueue = ConversionQueue()
    @State private var showQueueDetails = true

    private let historyStore = ConversionHistoryStore()

    private var supportedFormats: [ConversionFormat] {
        ConversionFormat.supportedFormats(for: selectedType)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            pickerSection
            settingsSection
            fileSection
            outputSection
            
            if !conversionQueue.items.isEmpty {
                Divider()
                queueSection
            }

            Divider()
            historySection
            
            actionSection
            statusSection
            Spacer()
        }
        .padding(24)
        .frame(minWidth: 720, minHeight: 600)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: selectedType.allowedContentTypes,
            allowsMultipleSelection: true
        ) { result in
            handleImport(result)
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .sheet(item: $editingItem) { item in
            QueueItemEditor(item: item)
        }
        .onChange(of: selectedType) { _ in
            if let first = supportedFormats.first {
                selectedFormat = first
            }
        }
        .onChange(of: conversionQueue.isProcessing) { isProcessing in
            guard !isProcessing else { return }
            let completed = conversionQueue.items.filter { item in
                if case .completed = item.status {
                    return true
                }
                return false
            }.count
            refreshHistoryFromQueue()
            statusMessage = "Cola procesada: \(completed)/\(conversionQueue.items.count) completados."
        }
        .onAppear {
            historyEntries = historyStore.load()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("JUST4CONVERT")
                .font(.system(size: 26, weight: .bold))
            Text("MVP nativo para conversion de audio, video e imagenes")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }

    private var pickerSection: some View {
        HStack(spacing: 16) {
            Picker("Tipo", selection: $selectedType) {
                ForEach(ConversionType.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)

            Picker("Formato", selection: $selectedFormat) {
                ForEach(supportedFormats) { format in
                    Text(format.displayLabel)
                        .tag(format)
                        .disabled(!format.isSelectableOutput)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Presets")
                .font(.system(size: 12, weight: .semibold))
            switch selectedType {
            case .audio:
                Picker("Bitrate", selection: $audioBitrate) {
                    ForEach(AudioBitrateOption.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.menu)
            case .video:
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Picker("Resolucion", selection: $videoResolution) {
                            ForEach(VideoResolutionOption.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .pickerStyle(.menu)

                        Picker("FPS", selection: $videoFps) {
                            ForEach(VideoFpsOption.allCases) { option in
                                Text(option.label).tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    HStack(spacing: 12) {
                        Picker("Codec", selection: $videoCodec) {
                            ForEach(VideoCodecOption.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .pickerStyle(.menu)

                        Picker("Bitrate", selection: $videoBitrate) {
                            ForEach(VideoBitrateOption.allCases) { option in
                                Text(option.label).tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
            case .image:
                Picker("Calidad", selection: $imageQuality) {
                    ForEach(ImageQualityOption.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    private var fileSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Archivos de entrada")
                .font(.system(size: 12, weight: .semibold))
            
            if selectedFiles.isEmpty {
                HStack {
                    Text("Sin archivos seleccionados")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Seleccionar archivos") { showImporter = true }
                    Button("Agregar carpeta") { pickInputFolder() }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(selectedFiles, id: \.self) { file in
                        HStack(spacing: 8) {
                            Image(systemName: "doc.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 10))
                            Text(file.lastPathComponent)
                                .font(.system(size: 11))
                                .lineLimit(1)
                            Spacer()
                            Button(action: {
                                selectedFiles.removeAll { $0 == file }
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    Button("+ Agregar más archivos") {
                        showImporter = true
                    }
                    .font(.system(size: 11))

                    Button("+ Agregar carpeta") {
                        pickInputFolder()
                    }
                    .font(.system(size: 11))
                }
                .padding(8)
                .background(Color(.controlBackgroundColor))
                .cornerRadius(4)
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    handleDrop(providers)
                }
            }
        }
    }

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Carpeta de salida")
                .font(.system(size: 12, weight: .semibold))
            HStack {
                Text(outputDirectory?.path ?? "Usar misma carpeta del archivo")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Spacer()
                Button("Elegir carpeta") {
                    pickOutputDirectory()
                }
            }
            Text("Plantilla salida: {name} {format} {date}")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            TextField("{name}_{format}", text: $outputNameTemplate)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var actionSection: some View {
        HStack(spacing: 12) {
            Button(action: { addToQueue() }) {
                Text("Agregar a cola")
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedFiles.isEmpty || outputDirectory == nil)

            if !conversionQueue.items.isEmpty {
                if conversionQueue.isProcessing {
                    Button(action: { conversionQueue.cancel() }) {
                        Text("Cancelar Cola")
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else {
                    Button(action: { conversionQueue.processQueue() }) {
                        Text("Procesar cola")
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button(action: { conversionQueue.clear() }) {
                    Text("Limpiar cola")
                }
                .buttonStyle(.bordered)
                .disabled(conversionQueue.isProcessing)
            }
            
            Button(action: { reset() }) {
                Text("Reiniciar")
            }
            .buttonStyle(.bordered)
        }
    }
    
    private var queueSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cola de conversion (\(conversionQueue.items.count))")
                .font(.system(size: 12, weight: .semibold))
            
            if conversionQueue.isProcessing {
                ProgressView(value: conversionQueue.totalProgress)
                    .controlSize(.small)
            }
            
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(conversionQueue.items) { item in
                        queueItemView(item)
                    }
                }
            }
            .frame(maxHeight: 150)
        }
    }
    
    private func queueItemView(_ item: QueuedConversion) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: statusIcon(for: item.status))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(statusColor(for: item.status))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                    Text("\(item.status.displayName) • \(item.conversionFormat.rawValue.uppercased())")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if item.progress > 0 && item.progress < 1 {
                    ProgressView(value: item.progress)
                        .frame(width: 60)
                        .controlSize(.mini)
                }

                if case .failed = item.status {
                    Button("Ver error") {
                        errorMessage = item.status.displayName
                        showErrorAlert = true
                    }
                    .font(.system(size: 10))
                    .buttonStyle(.bordered)

                    Button("Reintentar") {
                        statusMessage = "Reintentando \(item.displayName)"
                        conversionQueue.retryItem(item)
                    }
                    .font(.system(size: 10))
                    .buttonStyle(.borderedProminent)
                    .disabled(conversionQueue.isProcessing)
                }

                Button("Editar") {
                    editingItem = item
                }
                .font(.system(size: 10))
                .buttonStyle(.bordered)
                
                if case .completed = item.status {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 12))
                }
            }
            .padding(8)
            .background(Color(.controlBackgroundColor))
            .cornerRadius(4)

            if let eta = item.estimatedRemaining, eta > 0 {
                Text("ETA: \(formattedEta(eta))")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func statusIcon(for status: ConversionStatus) -> String {
        switch status {
        case .pending:
            return "hourglass"
        case .processing:
            return "hourglass.circle.fill"
        case .completed:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.circle.fill"
        }
    }
    
    private func statusColor(for status: ConversionStatus) -> Color {
        switch status {
        case .pending:
            return .gray
        case .processing:
            return .blue
        case .completed:
            return .green
        case .failed:
            return .red
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Estado")
                .font(.system(size: 12, weight: .semibold))
            Text(statusMessage)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Historial")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button(showHistory ? "Ocultar" : "Mostrar") {
                    showHistory.toggle()
                }
                .font(.system(size: 11))

                Button("Limpiar") {
                    historyStore.clear()
                    historyEntries = []
                }
                .font(.system(size: 11))
            }

            if showHistory {
                if historyEntries.isEmpty {
                    Text("Sin historial")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(historyEntries) { entry in
                                HStack {
                                    Text(entry.name)
                                        .font(.system(size: 11, weight: .medium))
                                        .lineLimit(1)
                                    Spacer()
                                    Text(entry.format.rawValue.uppercased())
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                    Text(formattedHistoryDate(entry.date))
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)

                                    Button("Abrir") {
                                        NSWorkspace.shared.open(entry.outputURL)
                                    }
                                    .font(.system(size: 10))

                                    Button("Revelar") {
                                        NSWorkspace.shared.activateFileViewerSelecting([entry.outputURL])
                                    }
                                    .font(.system(size: 10))
                                }
                                .padding(8)
                                .background(Color(.controlBackgroundColor))
                                .cornerRadius(4)
                            }
                        }
                    }
                    .frame(maxHeight: 160)
                }
            }
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            selectedFiles.append(contentsOf: urls)
            statusMessage = "Agregados \(urls.count) archivo(s)."
        case .failure(let error):
            statusMessage = "Error al seleccionar archivos: \(error.localizedDescription)"
        }
    }

    private func pickOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Seleccionar"

        if panel.runModal() == .OK {
            outputDirectory = panel.url
            statusMessage = "Carpeta de salida configurada."
        }
    }

    private func addToQueue() {
        guard let outputDir = outputDirectory else {
            statusMessage = "Selecciona una carpeta de salida primero."
            return
        }

        let settings = ConversionSettings(
            audioBitrate: audioBitrate,
            videoResolution: videoResolution,
            videoFps: videoFps,
            videoCodec: videoCodec,
            videoBitrate: videoBitrate,
            imageQuality: imageQuality
        )

        for fileURL in selectedFiles {
            let item = QueuedConversion(
                inputURL: fileURL,
                outputDirectory: outputDir,
                conversionType: selectedType,
                conversionFormat: selectedFormat,
                settings: settings,
                outputNameTemplate: outputNameTemplate
            )
            conversionQueue.addItem(item)
        }

        statusMessage = "Agregados \(selectedFiles.count) archivo(s) a la cola."
        selectedFiles.removeAll()
    }

    private func processQueue() {
        conversionQueue.processQueue()
        statusMessage = "Procesando cola..."
    }

    private func reset() {
        selectedFiles.removeAll()
        outputDirectory = nil
        audioBitrate = .bps192
        videoResolution = .original
        videoFps = .original
        videoCodec = .h264
        videoBitrate = .auto
        imageQuality = .q85
        outputNameTemplate = "{name}_{format}"
        conversionQueue.clear()
        statusMessage = "Reiniciado. Selecciona archivos para convertir."
    }

    private func refreshHistoryFromQueue() {
        let completedItems = conversionQueue.items.compactMap { item -> ConversionHistoryEntry? in
            guard case .completed = item.status, let outputURL = item.outputURL else {
                return nil
            }
            return ConversionHistoryEntry(
                id: UUID(),
                name: outputURL.lastPathComponent,
                outputURL: outputURL,
                format: item.conversionFormat,
                date: Date()
            )
        }

        if completedItems.isEmpty {
            return
        }

        for entry in completedItems {
            historyStore.append(entry: entry)
        }

        historyEntries = historyStore.load()
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

    private func pickInputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Seleccionar"

        if panel.runModal() == .OK, let folderURL = panel.url {
            let newFiles = collectFiles(in: folderURL, allowedTypes: selectedType.allowedContentTypes)
            selectedFiles.append(contentsOf: newFiles)
            statusMessage = "Agregados \(newFiles.count) archivo(s) desde carpeta."
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        var droppedURLs: [URL] = []

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    defer { group.leave() }
                    if let data = item as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil) {
                        droppedURLs.append(url)
                    } else if let url = item as? URL {
                        droppedURLs.append(url)
                    }
                }
            }
        }

        group.notify(queue: .main) {
            let newFiles = resolveDroppedURLs(droppedURLs)
            selectedFiles.append(contentsOf: newFiles)
            statusMessage = "Agregados \(newFiles.count) archivo(s) por drop."
        }

        return true
    }

    private func resolveDroppedURLs(_ urls: [URL]) -> [URL] {
        var results: [URL] = []
        let allowedTypes = selectedType.allowedContentTypes

        for url in urls {
            if let values = try? url.resourceValues(forKeys: [.isDirectoryKey]),
               values.isDirectory == true {
                results.append(contentsOf: collectFiles(in: url, allowedTypes: allowedTypes))
                continue
            }

            if let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType,
               allowedTypes.contains(where: { contentType.conforms(to: $0) }) {
                results.append(url)
            }
        }

        return results
    }

    private func collectFiles(in folderURL: URL, allowedTypes: [UTType]) -> [URL] {
        var results: [URL] = []
        let resourceKeys: Set<URLResourceKey> = [.isDirectoryKey, .contentTypeKey]
        let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            if let values = try? fileURL.resourceValues(forKeys: resourceKeys),
               values.isDirectory == true {
                continue
            }

            if let contentType = try? fileURL.resourceValues(forKeys: [.contentTypeKey]).contentType {
                if allowedTypes.contains(where: { contentType.conforms(to: $0) }) {
                    results.append(fileURL)
                }
            }
        }

        return results
    }

    private func formattedEta(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds))
        let minutes = totalSeconds / 60
        let remaining = totalSeconds % 60
        if minutes > 0 {
            return "\(minutes)m \(remaining)s"
        }
        return "\(remaining)s"
    }
}

private struct QueueItemEditor: View {
    @ObservedObject var item: QueuedConversion

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Editar presets")
                .font(.system(size: 16, weight: .semibold))

            Text(item.displayName)
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            switch item.conversionType {
            case .audio:
                Picker("Bitrate", selection: bindingAudioBitrate) {
                    ForEach(AudioBitrateOption.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.menu)

                formatPicker
            case .video:
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Resolucion", selection: bindingVideoResolution) {
                        ForEach(VideoResolutionOption.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.menu)

                    Picker("FPS", selection: bindingVideoFps) {
                        ForEach(VideoFpsOption.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.menu)

                    Picker("Codec", selection: bindingVideoCodec) {
                        ForEach(VideoCodecOption.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.menu)

                    Picker("Bitrate", selection: bindingVideoBitrate) {
                        ForEach(VideoBitrateOption.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.menu)

                    formatPicker
                }
            case .image:
                Picker("Calidad", selection: bindingImageQuality) {
                    ForEach(ImageQualityOption.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.menu)

                formatPicker
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 360, height: 240)
    }

    private var bindingAudioBitrate: Binding<AudioBitrateOption> {
        Binding(
            get: { item.settings.audioBitrate },
            set: { item.settings.audioBitrate = $0 }
        )
    }

    private var bindingVideoResolution: Binding<VideoResolutionOption> {
        Binding(
            get: { item.settings.videoResolution },
            set: { item.settings.videoResolution = $0 }
        )
    }

    private var bindingVideoFps: Binding<VideoFpsOption> {
        Binding(
            get: { item.settings.videoFps },
            set: { item.settings.videoFps = $0 }
        )
    }

    private var bindingVideoCodec: Binding<VideoCodecOption> {
        Binding(
            get: { item.settings.videoCodec },
            set: { item.settings.videoCodec = $0 }
        )
    }

    private var bindingVideoBitrate: Binding<VideoBitrateOption> {
        Binding(
            get: { item.settings.videoBitrate },
            set: { item.settings.videoBitrate = $0 }
        )
    }

    private var bindingImageQuality: Binding<ImageQualityOption> {
        Binding(
            get: { item.settings.imageQuality },
            set: { item.settings.imageQuality = $0 }
        )
    }

    private var formatPicker: some View {
        Picker("Formato", selection: bindingOutputFormat) {
            ForEach(ConversionFormat.supportedFormats(for: item.conversionType)) { format in
                Text(format.displayLabel)
                    .tag(format)
                    .disabled(!format.isSelectableOutput)
            }
        }
        .pickerStyle(.menu)
    }

    private var bindingOutputFormat: Binding<ConversionFormat> {
        Binding(
            get: { item.conversionFormat },
            set: { item.conversionFormat = $0 }
        )
    }
}
