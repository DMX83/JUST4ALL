import SwiftUI
import AppKit

private enum BatchItemStatus {
    case pending
    case processing
    case success
    case failed
    case cancelled
}

private struct BatchItemResult {
    var status: BatchItemStatus
    var outputURL: URL?
    var errorMessage: String?
    var mode: EnhancementMode?
}

private enum EnhancementMode: String {
    case local = "Procesado Pro"
    case ai = "IA"
}

private enum ActivityLogFilter: String, CaseIterable, Identifiable {
    case all = "Todos"
    case pro = "PRO"
    case ai = "IA"
    case errors = "Errores"

    var id: String { rawValue }
}

private enum PreviewKind: String {
    case original = "Original"
    case pro = "Procesado Pro"
    case ai = "IA"
}

private struct PreviewLightboxItem: Identifiable {
    let kind: PreviewKind
    let image: NSImage
    let badge: String?
    let summary: String?

    var id: PreviewKind { kind }
}

private final class OutputSettings: ObservableObject {
    @Published var format: OutputFormat
    @Published var quality: Double
    @Published var exportProfile: ExportProfile
    @Published var hasUserTouchedOutputSettings: Bool

    init(
        format: OutputFormat = .preferredDefault,
        quality: Double = OutputFormat.preferredQualityDefault,
        exportProfile: ExportProfile = .original,
        hasUserTouchedOutputSettings: Bool = false
    ) {
        self.format = format
        self.quality = quality
        self.exportProfile = exportProfile
        self.hasUserTouchedOutputSettings = hasUserTouchedOutputSettings
    }

    func resetToQualityDefaults() {
        hasUserTouchedOutputSettings = false
        format = .preferredDefault
        quality = OutputFormat.preferredQualityDefault
        exportProfile = .original
    }
}

private struct AIResolutionCacheKey: Hashable {
    let fileURL: URL
    let basePreset: EnhancementPreset
    let baseFormat: OutputFormat
}

struct ContentView: View {
    @State private var inputFiles: [URL] = []
    @State private var outputDirectory: URL?
    @State private var preset: EnhancementPreset = .auto
    @StateObject private var outputSettings: OutputSettings
    @State private var statusMessage = "Selecciona imágenes para iniciar"
    @State private var isProcessing = false
    @State private var processedCount = 0
    @State private var failedCount = 0
    @State private var progress: Double = 0
    @State private var logs: [String] = []
    @State private var selectedPreviewURL: URL?
    @State private var originalPreviewImage: NSImage?
    @State private var proPreviewImage: NSImage?
    @State private var aiPreviewImage: NSImage?
    @State private var isGeneratingPreview = false
    @State private var batchResults: [URL: BatchItemResult] = [:]
    @State private var batchTask: Task<Void, Never>?
    @State private var cancelRequested = false
    @State private var historyEntries: [PictHistoryEntry] = []
    @State private var isAnalyzingWithAI = false
    @State private var aiStatusMessage = "IA lista"
    @State private var aiPromptHD = ""
    @State private var aiSuggestedPresetForRun: String?
    @State private var aiSuggestedQualityForRun: Double?
    @State private var aiReasonForRun: String?
    @State private var aiTuningForRun: AIEnhancementTuning?
    @State private var aiRecipeForRun: EnhancementRecipe?
    @State private var aiResolutionCache: [AIResolutionCacheKey: AIRunResolution] = [:]
    @State private var storeFullAIPromptInHistory = false
    @State private var selectedMode: EnhancementMode = .local
    @State private var activityFilter: ActivityLogFilter = .all
    @State private var previewTask: Task<Void, Never>?
    @State private var previewRequestID = UUID()
    @State private var previewNeedsRefresh = false
    @State private var effectivePreviewPreset: EnhancementPreset = .auto
    @State private var effectivePreviewScene: ImageEnhancer.SceneType?
    @State private var isShowingPreviewLightbox = false
    @State private var lightboxSelection: PreviewKind = .original

    private let enhancer = ImageEnhancer()
    private let historyStore = PictHistoryStore()
    private let openAIAdvisor = OpenAIImageAdvisor()
    private let supportedExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "webp", "tif", "tiff", "bmp", "gif"]

    init(
        initialFormat: OutputFormat = .preferredDefault,
        initialQuality: Double = OutputFormat.preferredQualityDefault
    ) {
        _outputSettings = StateObject(
            wrappedValue: OutputSettings(
                format: initialFormat,
                quality: initialQuality,
                exportProfile: .original,
                hasUserTouchedOutputSettings: false
            )
        )
    }

    var body: some View {
        ScrollView {
            mainLayout
        }
            .sheet(isPresented: $isShowingPreviewLightbox) {
                PreviewLightboxView(
                    items: availablePreviewLightboxItems,
                    selectedKind: $lightboxSelection
                )
            }
            .onChange(of: preset) { _ in
                invalidateProcessedPreview()
            }
            .onChange(of: selectedPreviewURL) { _ in
                preparePreviewForSelection()
            }
            .onChange(of: selectedMode) { _ in
                invalidateProcessedPreview()
            }
            .onAppear {
                applyInitialOutputDefaults()
                historyEntries = historyStore.load()
                if aiPromptHD.isEmpty {
                    aiPromptHD = OpenAIImageAdvisor.defaultHDPrompt(
                        fileName: selectedPreviewURL?.lastPathComponent ?? "imagen",
                        width: 0,
                        height: 0,
                        currentPreset: preset,
                        currentFormat: activeFormat
                    )
                }
                preparePreviewForSelection()
                DispatchQueue.main.async {
                    applyInitialOutputDefaults()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    applyInitialOutputDefaults()
                }
            }
    }

    private func applyInitialOutputDefaults() {
        guard inputFiles.isEmpty else { return }
        outputSettings.resetToQualityDefaults()
    }

    private var activeFormat: OutputFormat {
        outputSettings.hasUserTouchedOutputSettings ? outputSettings.format : .preferredDefault
    }

    private var activeQuality: Double {
        outputSettings.hasUserTouchedOutputSettings ? outputSettings.quality : OutputFormat.preferredQualityDefault
    }

    private var qualityBinding: Binding<Double> {
        Binding(
            get: { activeQuality },
            set: { newValue in
                outputSettings.hasUserTouchedOutputSettings = true
                outputSettings.quality = newValue
            }
        )
    }

    private func selectOutputFormat(_ newValue: OutputFormat) {
        outputSettings.hasUserTouchedOutputSettings = true
        outputSettings.format = newValue
        if !newValue.supportsLossyQuality {
            outputSettings.quality = 1.0
        }
    }

    private var outputFormatLabel: String {
        activeFormat.rawValue
    }

    private var mainLayout: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            configurationSection
            modeSelectorSection
            if aiRecipeForRun != nil {
                aiRecipeSection
            }
            actionSection
            outputSection
            progressSection
            imagesSection
            beforeAfterSection
            activitySection
            historySection
            Text(statusMessage)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .padding(24)
        .frame(minWidth: 860, minHeight: 620, alignment: .topLeading)
    }

    private var availablePreviewLightboxItems: [PreviewLightboxItem] {
        var items: [PreviewLightboxItem] = []

        if let originalPreviewImage {
            items.append(
                PreviewLightboxItem(
                    kind: .original,
                    image: originalPreviewImage,
                    badge: nil,
                    summary: nil
                )
            )
        }

        if let proPreviewImage {
            items.append(
                PreviewLightboxItem(
                    kind: .pro,
                    image: proPreviewImage,
                    badge: "PRO",
                    summary: proPreviewSummary
                )
            )
        }

        if let aiPreviewImage {
            items.append(
                PreviewLightboxItem(
                    kind: .ai,
                    image: aiPreviewImage,
                    badge: "IA",
                    summary: aiRecipeForRun.map(aiRecipeSummary)
                )
            )
        }

        return items
    }

    private var configurationSection: some View {
        HStack(spacing: 12) {
            Picker("Preset", selection: $preset) {
                ForEach(EnhancementPreset.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.menu)

            Menu {
                ForEach(OutputFormat.pickerOrder) { option in
                    Button {
                        selectOutputFormat(option)
                    } label: {
                        if option == activeFormat {
                            Label(option.rawValue, systemImage: "checkmark")
                        } else {
                            Text(option.rawValue)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text("Formato")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text(outputFormatLabel)
                        .font(.system(size: 13, weight: .semibold))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            Picker("Destino", selection: $outputSettings.exportProfile) {
                ForEach(ExportProfile.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.menu)

            if activeFormat.supportsLossyQuality {
                HStack(spacing: 6) {
                    Text("Calidad")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Slider(value: qualityBinding, in: 0.5...1.0)
                        .frame(width: 120)
                    Text("\(Int(activeQuality * 100))%")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(width: 38, alignment: .trailing)
                }
            }
        }
    }

    private var actionSection: some View {
        HStack(spacing: 10) {
            Button("Seleccionar imágenes") { pickImages() }
            Button("Agregar carpeta") { pickFolder() }
            Button("Elegir salida") { pickOutputDirectory() }
            Button("Limpiar") { clearAll() }
                .disabled(isProcessing)

            if isProcessing {
                Button("Cancelar lote") { cancelBatch() }
                    .buttonStyle(.bordered)
            }

            Spacer()

            Button(isProcessing ? "Procesando..." : "Mejorar lote") {
                processBatch()
            }
            .buttonStyle(.borderedProminent)
            .disabled(inputFiles.isEmpty || isProcessing)
        }
    }

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Salida")
                .font(.system(size: 12, weight: .semibold))
            Text(outputDirectory?.path ?? "Misma carpeta de cada imagen")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineLimit(1)
            Text("Perfil de export: \(outputSettings.exportProfile.rawValue)")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var progressSection: some View {
        if isProcessing || progress > 0 {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
            Text("\(processedCount + failedCount)/\(max(inputFiles.count, 1)) procesadas")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    private var imagesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Imágenes")
                .font(.system(size: 12, weight: .semibold))

            if inputFiles.isEmpty {
                Text("Sin imágenes seleccionadas")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(6)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(inputFiles, id: \.self) { file in
                            Button {
                                selectedPreviewURL = file
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: selectedPreviewURL == file ? "photo.fill.on.rectangle.fill" : "photo")
                                        .font(.system(size: 10))
                                        .foregroundColor(selectedPreviewURL == file ? .accentColor : .secondary)

                                    Text(file.lastPathComponent)
                                        .font(.system(size: 11))
                                        .lineLimit(1)

                                    itemStatusView(for: file)

                                    Spacer()

                                    if shouldShowRetryButton(for: file) {
                                        Button("Reintentar") { retryItem(file) }
                                            .font(.system(size: 10, weight: .semibold))
                                            .buttonStyle(.bordered)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 2)
                        }
                    }
                }
                .frame(maxHeight: 170)
                .padding(10)
                .background(Color(.controlBackgroundColor))
                .cornerRadius(6)
            }
        }
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Actividad")
                    .font(.system(size: 12, weight: .semibold))

                Picker("Filtro", selection: $activityFilter) {
                    ForEach(ActivityLogFilter.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)

                Spacer()
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(filteredLogs.indices, id: \.self) { index in
                        Text(filteredLogs[index])
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxHeight: 140)
            .padding(10)
            .background(Color(.controlBackgroundColor))
            .cornerRadius(6)
        }
    }

    private var aiRecipeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Receta IA")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if let recipe = aiRecipeForRun {
                    Text(recipe.scene)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }

            if let recipe = aiRecipeForRun {
                VStack(alignment: .leading, spacing: 6) {
                    Text(recipe.objective)
                        .font(.system(size: 11))
                    Text(aiDecisionExplanation(recipe))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    if !aiDecisionHighlights(recipe).isEmpty {
                        Text(aiDecisionHighlights(recipe).joined(separator: " · "))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    Text(aiRecipeSummary(recipe))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color(.controlBackgroundColor))
                .cornerRadius(6)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text("JUST4PICT")
                    .font(.system(size: 26, weight: .bold))
                Text(BuildInfo.displayLabel)
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.2))
                    .foregroundColor(.orange)
                    .clipShape(Capsule())
            }
            Text("Edición y mejoramiento automático de imágenes por lotes")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }

    private var modeSelectorSection: some View {
        HStack(spacing: 10) {
            if selectedMode == .local {
                Button("✓ Procesado Pro") {
                    selectLocalMode()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isProcessing)
            } else {
                Button("Procesado Pro") {
                    selectLocalMode()
                }
                .buttonStyle(.bordered)
                .disabled(isProcessing)
            }

            if selectedMode == .ai {
                Button(isAnalyzingWithAI ? "IA analizando..." : "✓ IA") {
                    Task { await selectAIMode() }
                }
                .buttonStyle(.borderedProminent)
                .disabled((selectedPreviewURL ?? inputFiles.first) == nil || isAnalyzingWithAI || isProcessing)
            } else {
                Button(isAnalyzingWithAI ? "IA analizando..." : "IA") {
                    Task { await selectAIMode() }
                }
                .buttonStyle(.bordered)
                .disabled((selectedPreviewURL ?? inputFiles.first) == nil || isAnalyzingWithAI || isProcessing)
            }

            Text(modeStatusText)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)

            Spacer()
        }
    }

    private var modeStatusText: String {
        switch selectedMode {
        case .local:
            if let autoDecision = autoDecisionLabel {
                return "Modo activo: Procesado Pro (motor local) · AUTO decide \(autoDecision)"
            }
            return "Modo activo: Procesado Pro (motor local)"
        case .ai:
            return isAnalyzingWithAI ? "IA analizando imagen..." : "Modo activo: IA · asesor inteligente + motor local · \(aiStatusMessage)"
        }
    }

    private var autoDecisionLabel: String? {
        guard preset == .auto else { return nil }
        switch effectivePreviewScene {
        case .portrait:
            return "Retrato"
        case .document:
            return "Documento"
        case .landscape:
            return "Paisaje"
        case .ecommerce:
            return "Ecommerce"
        case .darkPhoto:
            return "Foto oscura"
        case .generic, .none:
            return "General"
        }
    }

    private var filteredLogs: [String] {
        logs.filter { log in
            switch activityFilter {
            case .all:
                return true
            case .pro:
                return log.contains("[PRO]")
            case .ai:
                return log.contains("[IA]")
            case .errors:
                return log.contains("❌") || log.contains("⚠️")
            }
        }
    }

    private var beforeAfterSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Preview Mejora")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if let selectedPreviewURL {
                    Text(selectedPreviewURL.lastPathComponent)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Text("Modo: \(selectedMode.rawValue)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }

            Group {
                if isGeneratingPreview {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Generando preview...")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                } else if let originalPreviewImage {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Button {
                                Task { await enhancePreview() }
                            } label: {
                                Label("Enhance", systemImage: "wand.and.stars")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(selectedPreviewURL == nil || isGeneratingPreview || isAnalyzingWithAI)

                            Text(previewNeedsRefresh ? "La preview está desactualizada. Pulsa Enhance para regenerarla." : "Pulsa Enhance para generar la mejora.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }

                        HStack(alignment: .top, spacing: 12) {
                            previewCard(title: "Original", badge: nil, image: originalPreviewImage, summary: nil, placeholder: "Sin original")
                            previewCard(title: "Procesado Pro", badge: "PRO", image: proPreviewImage, summary: proPreviewSummary, placeholder: "Pulsa Enhance para generar preview PRO")
                            previewCard(title: "IA", badge: "IA", image: aiPreviewImage, summary: aiRecipeForRun.map(aiRecipeSummary), placeholder: aiTuningForRun == nil ? "Activa IA y pulsa Enhance para comparar" : "Pulsa Enhance para generar preview IA")
                        }
                    }
                } else {
                    Text("Selecciona una imagen para ver la comparación")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                }
            }
            .padding(10)
            .background(Color(.controlBackgroundColor))
            .cornerRadius(6)
        }
    }

    private func previewCard(title: String, badge: String?, image: NSImage?, summary: String?, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)

                if let badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(badge == "IA" ? Color.purple.opacity(0.14) : Color.blue.opacity(0.12))
                        .foregroundColor(badge == "IA" ? .purple : .blue)
                        .clipShape(Capsule())
                }

                if image != nil {
                    Button {
                        openPreviewLightbox(for: title)
                    } label: {
                        Label("Ampliar", systemImage: "arrow.up.left.and.arrow.down.right")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.plain)
                    .help("Abrir visor ampliado")
                    .foregroundColor(.secondary)
                }
            }

            if let summary, !summary.isEmpty {
                Text(summary)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Group {
                if let image {
                    ZStack {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()

                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                    }
                    .highPriorityGesture(
                        TapGesture(count: 2)
                            .onEnded {
                                openPreviewLightbox(for: title)
                            }
                    )
                } else {
                    Text(placeholder)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.vertical, 12)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: 250)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func openPreviewLightbox(for title: String) {
        guard !availablePreviewLightboxItems.isEmpty else { return }

        switch title {
        case PreviewKind.original.rawValue:
            lightboxSelection = .original
        case PreviewKind.pro.rawValue:
            lightboxSelection = .pro
        case PreviewKind.ai.rawValue:
            lightboxSelection = .ai
        default:
            lightboxSelection = availablePreviewLightboxItems.first?.kind ?? .original
        }

        if availablePreviewLightboxItems.contains(where: { $0.kind == lightboxSelection }) {
            isShowingPreviewLightbox = true
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Historial")
                .font(.system(size: 12, weight: .semibold))

            if historyEntries.isEmpty {
                Text("Sin historial de salidas")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(6)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(historyEntries) { entry in
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.inputFileName)
                                        .font(.system(size: 11, weight: .semibold))
                                        .lineLimit(1)
                                    Text(URL(fileURLWithPath: entry.outputPath).lastPathComponent)
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                    if let reason = entry.aiReason, !reason.isEmpty {
                                        Text("IA: \(reason)")
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                    if let tuning = entry.aiTuningSummary, !tuning.isEmpty {
                                        Text("Ajustes IA: \(tuning)")
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                    if let summary = entry.aiPromptSummary, !summary.isEmpty {
                                        Text("Prompt: \(summary)")
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }

                                Spacer()

                                Text(entry.preset)
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)

                                if entry.aiSuggestedPreset != nil {
                                    Text("IA")
                                        .font(.system(size: 9, weight: .semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.purple.opacity(0.14))
                                        .foregroundColor(.purple)
                                        .clipShape(Capsule())
                                } else {
                                    Text("PRO")
                                        .font(.system(size: 9, weight: .semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.12))
                                        .foregroundColor(.blue)
                                        .clipShape(Capsule())
                                }

                                Button("Abrir") {
                                    openOutput(path: entry.outputPath)
                                }
                                .font(.system(size: 10, weight: .semibold))
                                .buttonStyle(.bordered)

                                Button("Revelar") {
                                    revealOutput(path: entry.outputPath)
                                }
                                .font(.system(size: 10, weight: .semibold))
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
                .frame(maxHeight: 140)
                .padding(10)
                .background(Color(.controlBackgroundColor))
                .cornerRadius(6)
            }
        }
    }

    private func clearAll() {
        batchTask?.cancel()
        inputFiles.removeAll()
        logs.removeAll()
        processedCount = 0
        failedCount = 0
        progress = 0
        batchResults.removeAll()
        cancelRequested = false
        outputSettings.resetToQualityDefaults()
        selectedPreviewURL = nil
        originalPreviewImage = nil
        proPreviewImage = nil
        aiPreviewImage = nil
        effectivePreviewScene = nil
        effectivePreviewPreset = .auto
        aiResolutionCache.removeAll()
        previewTask?.cancel()
        statusMessage = "Selecciona imágenes para iniciar"
    }

    private func processBatch() {
        guard !inputFiles.isEmpty else { return }

        batchTask?.cancel()
        isProcessing = true
        processedCount = 0
        failedCount = 0
        progress = 0
        logs.removeAll()
        cancelRequested = false
        batchResults = Dictionary(uniqueKeysWithValues: inputFiles.map { ($0, BatchItemResult(status: .pending, outputURL: nil, errorMessage: nil, mode: nil)) })
        statusMessage = "Procesando \(inputFiles.count) imágenes..."

        let files = inputFiles
        let modeSnapshot = selectedMode

        batchTask = Task {
            let snapshot = await MainActor.run { () -> (
                mode: EnhancementMode,
                outputDirectory: URL?,
                preset: EnhancementPreset,
                format: OutputFormat,
                quality: Double,
                exportProfile: ExportProfile
            ) in
                return (
                    modeSnapshot,
                    outputDirectory,
                    preset,
                    activeFormat,
                    activeQuality,
                    outputSettings.exportProfile
                )
            }

            for (index, input) in files.enumerated() {
                if Task.isCancelled || cancelRequested {
                    await MainActor.run {
                        markRemainingAsCancelled(files: files, startingAt: index)
                        isProcessing = false
                        batchTask = nil
                        statusMessage = "Lote cancelado"
                        recomputeCounters(total: files.count)
                    }
                    return
                }

                await MainActor.run {
                    batchResults[input] = BatchItemResult(status: .processing, outputURL: nil, errorMessage: nil, mode: modeSnapshot)
                }

                let runResolution: AIRunResolution
                if modeSnapshot == .ai {
                    runResolution = await resolveAIRunConfiguration(
                        for: input,
                        basePreset: snapshot.preset,
                        baseFormat: snapshot.format,
                        baseQuality: snapshot.quality,
                        shouldUpdateUIState: false
                    )
                } else {
                    runResolution = AIRunResolution(
                        preset: snapshot.preset,
                        format: snapshot.format,
                        quality: snapshot.quality,
                        upscaleTargetLongSide: nil,
                        faceRestoreStrength: nil,
                        aiSuggestedPreset: nil,
                        aiSuggestedQuality: nil,
                        aiReason: nil,
                        aiPrompt: nil,
                        aiTuning: nil,
                        recipe: nil,
                        usedFallback: false
                    )
                }

                let destinationDirectory = snapshot.outputDirectory ?? input.deletingLastPathComponent()
                let outputURL = uniqueOutputURL(
                    for: input,
                    in: destinationDirectory,
                    format: runResolution.format,
                    mode: snapshot.mode
                )

                do {
                    try await runEnhancement(
                        inputURL: input,
                        outputURL: outputURL,
                        mode: snapshot.mode,
                        preset: runResolution.preset,
                        quality: runResolution.quality,
                        format: runResolution.format,
                        exportProfile: snapshot.exportProfile,
                        upscaleTargetLongSide: runResolution.upscaleTargetLongSide,
                        faceRestoreStrength: runResolution.faceRestoreStrength,
                        aiPrompt: runResolution.aiPrompt,
                        aiTuning: runResolution.aiTuning
                    )
                    await MainActor.run {
                        batchResults[input] = BatchItemResult(status: .success, outputURL: outputURL, errorMessage: nil, mode: modeSnapshot)
                        historyEntries = historyStore.prepend(
                            current: historyEntries,
                            inputFileName: input.lastPathComponent,
                            outputURL: outputURL,
                            preset: runResolution.preset,
                            format: runResolution.format,
                            aiSuggestedPreset: runResolution.aiSuggestedPreset,
                            aiSuggestedQuality: runResolution.aiSuggestedQuality,
                            aiReason: runResolution.aiReason,
                            aiTuningSummary: aiTuningSummary(runResolution.aiTuning),
                            aiPrompt: runResolution.aiPrompt,
                            storeFullPrompt: storeFullAIPromptInHistory
                        )
                        let fallbackSuffix = runResolution.usedFallback ? " (fallback local)" : ""
                        logs.insert("\(modeLogPrefix(modeSnapshot)) ✅ \(input.lastPathComponent) → \(outputURL.lastPathComponent)\(fallbackSuffix)", at: 0)
                        recomputeCounters(total: files.count)
                    }
                } catch {
                    await MainActor.run {
                        batchResults[input] = BatchItemResult(status: .failed, outputURL: nil, errorMessage: error.localizedDescription, mode: modeSnapshot)
                        logs.insert("\(modeLogPrefix(modeSnapshot)) ❌ \(input.lastPathComponent): \(error.localizedDescription)", at: 0)
                        recomputeCounters(total: files.count)
                    }
                }
            }

            await MainActor.run {
                isProcessing = false
                batchTask = nil
                recomputeCounters(total: files.count)
                statusMessage = "Finalizado: \(processedCount) OK, \(failedCount) con error"
            }
        }
    }

    private func cancelBatch() {
        cancelRequested = true
        batchTask?.cancel()
        statusMessage = "Cancelando lote..."
    }

    private func retryItem(_ file: URL) {
        guard !isProcessing else { return }
        guard let current = batchResults[file], current.status == .failed else { return }

        let modeSnapshot = selectedMode

        batchResults[file] = BatchItemResult(status: .processing, outputURL: nil, errorMessage: nil, mode: modeSnapshot)
        statusMessage = "Reintentando \(file.lastPathComponent)..."

        Task {
            let snapshot = await MainActor.run { () -> (
                mode: EnhancementMode,
                preset: EnhancementPreset,
                quality: Double,
                format: OutputFormat,
                outputDirectory: URL?,
                exportProfile: ExportProfile
            ) in
                (modeSnapshot, preset, activeQuality, activeFormat, outputDirectory, outputSettings.exportProfile)
            }

            let runResolution: AIRunResolution
            if modeSnapshot == .ai {
                runResolution = await resolveAIRunConfiguration(
                    for: file,
                    basePreset: snapshot.preset,
                    baseFormat: snapshot.format,
                    baseQuality: snapshot.quality,
                    shouldUpdateUIState: true
                )
            } else {
                    runResolution = AIRunResolution(
                        preset: snapshot.preset,
                        format: snapshot.format,
                        quality: snapshot.quality,
                        upscaleTargetLongSide: nil,
                        faceRestoreStrength: nil,
                        aiSuggestedPreset: nil,
                    aiSuggestedQuality: nil,
                    aiReason: nil,
                    aiPrompt: nil,
                    aiTuning: nil,
                    recipe: nil,
                    usedFallback: false
                )
            }

            let destinationDirectory = snapshot.outputDirectory ?? file.deletingLastPathComponent()
            let outputURL = uniqueOutputURL(
                for: file,
                in: destinationDirectory,
                format: runResolution.format,
                mode: modeSnapshot
            )

            do {
                try await runEnhancement(
                    inputURL: file,
                    outputURL: outputURL,
                    mode: snapshot.mode,
                    preset: runResolution.preset,
                    quality: runResolution.quality,
                    format: runResolution.format,
                    exportProfile: snapshot.exportProfile,
                    upscaleTargetLongSide: runResolution.upscaleTargetLongSide,
                    faceRestoreStrength: runResolution.faceRestoreStrength,
                    aiPrompt: runResolution.aiPrompt,
                    aiTuning: runResolution.aiTuning
                )
                await MainActor.run {
                    batchResults[file] = BatchItemResult(status: .success, outputURL: outputURL, errorMessage: nil, mode: modeSnapshot)
                    historyEntries = historyStore.prepend(
                        current: historyEntries,
                        inputFileName: file.lastPathComponent,
                        outputURL: outputURL,
                        preset: runResolution.preset,
                        format: runResolution.format,
                        aiSuggestedPreset: runResolution.aiSuggestedPreset,
                        aiSuggestedQuality: runResolution.aiSuggestedQuality,
                        aiReason: runResolution.aiReason,
                        aiTuningSummary: aiTuningSummary(runResolution.aiTuning),
                        aiPrompt: runResolution.aiPrompt,
                        storeFullPrompt: storeFullAIPromptInHistory
                    )
                    let fallbackSuffix = runResolution.usedFallback ? " (fallback local)" : ""
                    logs.insert("\(modeLogPrefix(modeSnapshot)) ✅ Reintento \(file.lastPathComponent) → \(outputURL.lastPathComponent)\(fallbackSuffix)", at: 0)
                    recomputeCounters(total: inputFiles.count)
                    statusMessage = "Reintento completado"
                }
            } catch {
                await MainActor.run {
                    batchResults[file] = BatchItemResult(status: .failed, outputURL: nil, errorMessage: error.localizedDescription, mode: modeSnapshot)
                    logs.insert("\(modeLogPrefix(modeSnapshot)) ❌ Reintento \(file.lastPathComponent): \(error.localizedDescription)", at: 0)
                    recomputeCounters(total: inputFiles.count)
                    statusMessage = "Reintento fallido"
                }
            }
        }
    }

    private func runEnhancement(
        inputURL: URL,
        outputURL: URL,
        mode: EnhancementMode,
        preset: EnhancementPreset,
        quality: Double,
        format: OutputFormat,
        exportProfile: ExportProfile,
        upscaleTargetLongSide: CGFloat?,
        faceRestoreStrength: Double?,
        aiPrompt: String?,
        aiTuning: AIEnhancementTuning?
    ) async throws {
        if mode == .ai {
            _ = resolvedAIPrompt(for: inputURL, preferredPrompt: aiPrompt)
        }

        try await Task.detached(priority: .userInitiated) {
            let worker = ImageEnhancer()
            try worker.enhance(
                inputURL: inputURL,
                outputURL: outputURL,
                preset: preset,
                quality: quality,
                format: format,
                exportProfile: exportProfile,
                upscaleTargetLongSide: upscaleTargetLongSide,
                faceRestoreStrength: faceRestoreStrength,
                tuning: aiTuning
            )
        }.value
    }

    private func markRemainingAsCancelled(files: [URL], startingAt index: Int) {
        guard index < files.count else { return }
        for candidate in files[index...] {
            guard let current = batchResults[candidate] else { continue }
            if current.status == .pending || current.status == .processing {
                batchResults[candidate] = BatchItemResult(status: .cancelled, outputURL: nil, errorMessage: "Cancelado por usuario", mode: current.mode)
            }
        }
    }

    private func recomputeCounters(total: Int) {
        let values = Array(batchResults.values)
        processedCount = values.filter { $0.status == .success }.count
        failedCount = values.filter { $0.status == .failed }.count

        let terminal = values.filter { result in
            result.status == .success || result.status == .failed || result.status == .cancelled
        }.count

        progress = total > 0 ? Double(terminal) / Double(total) : 0
    }

    private func shouldShowRetryButton(for file: URL) -> Bool {
        guard let result = batchResults[file] else { return false }
        return result.status == .failed && !isProcessing
    }

    @ViewBuilder
    private func itemStatusView(for file: URL) -> some View {
        if let result = batchResults[file] {
            let meta = statusMeta(for: result.status)

            HStack(spacing: 4) {
                Text(meta.title)
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(meta.color.opacity(0.12))
                    .foregroundColor(meta.color)
                    .clipShape(Capsule())

                if let mode = result.mode {
                    modeBadge(mode)
                }
            }
        }
    }

    private func modeBadge(_ mode: EnhancementMode) -> some View {
        Text(mode == .ai ? "IA" : "PRO")
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(mode == .ai ? Color.purple.opacity(0.14) : Color.blue.opacity(0.12))
            .foregroundColor(mode == .ai ? .purple : .blue)
            .clipShape(Capsule())
    }

    private func modeLogPrefix(_ mode: EnhancementMode) -> String {
        mode == .ai ? "[IA]" : "[PRO]"
    }

    private func statusMeta(for status: BatchItemStatus) -> (title: String, color: Color) {
        switch status {
        case .pending:
            return ("Pendiente", .secondary)
        case .processing:
            return ("Procesando", .blue)
        case .success:
            return ("OK", .green)
        case .failed:
            return ("Error", .red)
        case .cancelled:
            return ("Cancelado", .orange)
        }
    }

    @MainActor
    private func recommendWithAI() async {
        guard let fileURL = selectedPreviewURL ?? inputFiles.first else {
            aiStatusMessage = "Selecciona una imagen"
            return
        }

        await recommendWithAI(for: fileURL)
    }

    @MainActor
    private func recommendWithAI(for fileURL: URL) async {
        selectedMode = .ai

        isAnalyzingWithAI = true
        defer { isAnalyzingWithAI = false }

        _ = await resolveAIRunConfiguration(
            for: fileURL,
            basePreset: preset,
            baseFormat: activeFormat,
            baseQuality: activeQuality,
            shouldUpdateUIState: true
        )
    }

    private func selectLocalMode() {
        selectedMode = .local
        aiStatusMessage = "IA lista"
        aiSuggestedPresetForRun = nil
        aiSuggestedQualityForRun = nil
        aiReasonForRun = nil
        aiTuningForRun = nil
        aiRecipeForRun = nil
        logs.insert("[PRO] 🛠️ Modo Procesado Pro seleccionado", at: 0)
        invalidateProcessedPreview()
    }

    @MainActor
    private func selectAIMode() async {
        guard let fileURL = selectedPreviewURL ?? inputFiles.first else {
            aiStatusMessage = "Selecciona una imagen"
            return
        }
        await recommendWithAI(for: fileURL)
    }

    private func openOutput(path: String) {
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        } else {
            logs.insert("⚠️ Archivo no encontrado: \(url.lastPathComponent)", at: 0)
        }
    }

    private func revealOutput(path: String) {
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            logs.insert("⚠️ Archivo no encontrado: \(url.lastPathComponent)", at: 0)
        }
    }

    private func schedulePreviewRefresh() {
        previewTask?.cancel()
        let requestID = UUID()
        previewRequestID = requestID
        previewTask = Task {
            await refreshPreview(requestID: requestID)
        }
    }

    @MainActor
    private func enhancePreview() async {
        guard selectedPreviewURL != nil else { return }
        if selectedMode == .ai, aiTuningForRun == nil {
            await recommendWithAI()
            if aiTuningForRun == nil {
                return
            }
        }
        schedulePreviewRefresh()
    }

    private func imagePixelDimensions(for fileURL: URL) -> (width: Int, height: Int) {
        let image = NSImage(contentsOf: fileURL)
        return (Int(image?.size.width ?? 0), Int(image?.size.height ?? 0))
    }

    @MainActor
    private func applyAIResolutionToUI(_ resolution: AIRunResolution, for fileURL: URL, fromCache: Bool) {
        if let suggestedPreset = EnhancementPlanner.suggestedPreset(for: resolution) {
            preset = suggestedPreset
        }

        if let recipeFormat = resolution.recipe?.mappedExportFormat {
            outputSettings.hasUserTouchedOutputSettings = true
            outputSettings.format = recipeFormat
            if !recipeFormat.supportsLossyQuality {
                outputSettings.quality = OutputFormat.preferredQualityDefault
            }
        }

        if resolution.format.supportsLossyQuality {
            outputSettings.hasUserTouchedOutputSettings = true
            outputSettings.quality = resolution.quality
        }

        aiPromptHD = resolution.aiPrompt ?? aiPromptHD
        aiStatusMessage = resolution.aiReason ?? "IA lista"
        aiSuggestedPresetForRun = resolution.aiSuggestedPreset
        aiSuggestedQualityForRun = resolution.aiSuggestedQuality
        aiReasonForRun = resolution.aiReason
        aiTuningForRun = resolution.aiTuning
        aiRecipeForRun = resolution.recipe

        if resolution.usedFallback {
            logs.insert("[IA] ⚠️ IA no disponible para \(fileURL.lastPathComponent). Se usa fallback local.", at: 0)
        } else {
            let decisionSummary = aiDecisionLogSummary(for: resolution)
            let cacheSuffix = fromCache ? " · cache" : ""
            logs.insert("[IA] 🤖 IA aplicada a \(fileURL.lastPathComponent): \(decisionSummary)\(cacheSuffix)", at: 0)
        }

        invalidateProcessedPreview()
    }

    private func aiResolutionCacheKey(
        for fileURL: URL,
        basePreset: EnhancementPreset,
        baseFormat: OutputFormat
    ) -> AIResolutionCacheKey {
        AIResolutionCacheKey(
            fileURL: fileURL.standardizedFileURL,
            basePreset: basePreset,
            baseFormat: baseFormat
        )
    }

    private func resolveAIRunConfiguration(
        for fileURL: URL,
        basePreset: EnhancementPreset,
        baseFormat: OutputFormat,
        baseQuality: Double,
        shouldUpdateUIState: Bool
    ) async -> AIRunResolution {
        let cacheKey = aiResolutionCacheKey(
            for: fileURL,
            basePreset: basePreset,
            baseFormat: baseFormat
        )

        if let cached = await MainActor.run(body: { aiResolutionCache[cacheKey] }) {
            if shouldUpdateUIState {
                await MainActor.run {
                    applyAIResolutionToUI(cached, for: fileURL, fromCache: true)
                }
            }
            return cached
        }

        let dimensions = imagePixelDimensions(for: fileURL)

        do {
            let recommendation = try await openAIAdvisor.recommendHD(
                inputURL: fileURL,
                fileName: fileURL.lastPathComponent,
                width: dimensions.width,
                height: dimensions.height,
                currentPreset: basePreset,
                currentFormat: baseFormat
            )

            let resolution = EnhancementPlanner.resolve(
                recommendation: recommendation,
                basePreset: basePreset,
                baseFormat: baseFormat,
                baseQuality: baseQuality
            )

            if shouldUpdateUIState {
                await MainActor.run {
                    aiResolutionCache[cacheKey] = resolution
                    applyAIResolutionToUI(resolution, for: fileURL, fromCache: false)
                }
            } else {
                await MainActor.run {
                    aiResolutionCache[cacheKey] = resolution
                }
            }

            return resolution
        } catch {
            let fallback = EnhancementPlanner.fallbackPlan(
                fileName: fileURL.lastPathComponent,
                width: dimensions.width,
                height: dimensions.height,
                basePreset: basePreset,
                baseFormat: baseFormat,
                baseQuality: baseQuality
            )

            if shouldUpdateUIState {
                await MainActor.run {
                    aiStatusMessage = "IA no disponible, usando flujo local"
                    aiSuggestedPresetForRun = nil
                    aiSuggestedQualityForRun = nil
                    aiReasonForRun = nil
                    aiTuningForRun = nil
                    aiRecipeForRun = nil
                    aiPromptHD = fallback.aiPrompt ?? aiPromptHD
                    logs.insert("[IA] ⚠️ IA no disponible: \(error.localizedDescription)", at: 0)
                    invalidateProcessedPreview()
                }
            }

            return fallback
        }
    }

    private func resolvedAIPrompt(for inputURL: URL, preferredPrompt: String?) -> String {
        let trimmedPrompt = preferredPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedPrompt, !trimmedPrompt.isEmpty {
            return trimmedPrompt
        }
        return enhancer.promptForImageType(inputURL: inputURL)
    }

    @MainActor
    private func refreshPreview(requestID: UUID) async {
        guard let selectedPreviewURL else {
            originalPreviewImage = nil
            proPreviewImage = nil
            aiPreviewImage = nil
            previewNeedsRefresh = false
            return
        }

        isGeneratingPreview = true

        do {
            guard let original = NSImage(contentsOf: selectedPreviewURL) else {
                throw ImageEnhancerError.cannotLoadImage(selectedPreviewURL)
            }
            originalPreviewImage = original

            let proPreview = try enhancer.enhancedPreviewImage(inputURL: selectedPreviewURL, preset: preset)
            if Task.isCancelled || previewRequestID != requestID {
                isGeneratingPreview = false
                return
            }
            proPreviewImage = proPreview

            if let aiTuningForRun {
                _ = resolvedAIPrompt(for: selectedPreviewURL, preferredPrompt: aiPromptHD)
                let aiPreview = try enhancer.enhancedPreviewImage(
                    inputURL: selectedPreviewURL,
                    preset: preset,
                    tuning: aiTuningForRun,
                    faceRestoreStrength: aiRecipeForRun?.faceRestore.flatMap { $0.enabled ? ($0.strength ?? 0.5) : nil },
                    upscaleTargetLongSide: aiRecipeForRun?.upscaleTargetLongSide
                )
                if Task.isCancelled || previewRequestID != requestID {
                    isGeneratingPreview = false
                    return
                }
                aiPreviewImage = aiPreview
            } else {
                aiPreviewImage = nil
            }
            previewNeedsRefresh = false
        } catch {
            originalPreviewImage = nil
            proPreviewImage = nil
            aiPreviewImage = nil
            logs.insert("❌ Preview \(selectedPreviewURL.lastPathComponent): \(error.localizedDescription)", at: 0)
        }

        isGeneratingPreview = false
    }

    private func pickImages() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image]

        guard panel.runModal() == .OK else { return }
        mergeInputFiles(panel.urls)
        if selectedPreviewURL == nil {
            selectedPreviewURL = inputFiles.first
        }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let folder = panel.url else { return }

        do {
            let urls = try collectImages(in: folder)
            mergeInputFiles(urls)
            if selectedPreviewURL == nil {
                selectedPreviewURL = inputFiles.first
            }
        } catch {
            logs.insert("❌ No se pudo leer carpeta: \(error.localizedDescription)", at: 0)
        }
    }

    private func pickOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK else { return }
        outputDirectory = panel.url
    }

    private func mergeInputFiles(_ files: [URL]) {
        let normalized = files
            .filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
            .map { $0.standardizedFileURL }

        var current = Set(inputFiles.map(\.standardizedFileURL))
        for file in normalized where !current.contains(file) {
            inputFiles.append(file)
            current.insert(file)
        }

        if !normalized.isEmpty {
            statusMessage = "\(inputFiles.count) imágenes en cola"
            if selectedPreviewURL == nil {
                selectedPreviewURL = inputFiles.first
            }
            preparePreviewForSelection()
            if preset == .auto, let previewURL = selectedPreviewURL ?? inputFiles.first {
                let scene = enhancer.detectSceneType(inputURL: previewURL)
                logs.insert("[PRO] AUTO analizará \(previewURL.lastPathComponent) como \(autoDecisionLabel(for: scene))", at: 0)
            }
        }
    }

    @MainActor
    private func preparePreviewForSelection() {
        previewTask?.cancel()
        previewNeedsRefresh = false
        proPreviewImage = nil
        aiPreviewImage = nil

        guard let previewURL = selectedPreviewURL ?? inputFiles.first else {
            originalPreviewImage = nil
            effectivePreviewScene = nil
            effectivePreviewPreset = .auto
            return
        }

        if selectedPreviewURL == nil {
            selectedPreviewURL = previewURL
        }
        originalPreviewImage = NSImage(contentsOf: previewURL)
        effectivePreviewScene = enhancer.detectSceneType(inputURL: previewURL)
        effectivePreviewPreset = enhancer.effectivePreset(for: preset, inputURL: previewURL)
        previewNeedsRefresh = true
    }

    @MainActor
    private func invalidateProcessedPreview() {
        previewTask?.cancel()
        proPreviewImage = nil
        aiPreviewImage = nil
        previewNeedsRefresh = selectedPreviewURL != nil || !inputFiles.isEmpty
    }

    private func collectImages(in folder: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var result: [URL] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            if supportedExtensions.contains(url.pathExtension.lowercased()) {
                result.append(url)
            }
        }
        return result
    }

    private func uniqueOutputURL(
        for inputURL: URL,
        in directory: URL,
        format: OutputFormat,
        mode: EnhancementMode
    ) -> URL {
        let baseName = inputURL.deletingPathExtension().lastPathComponent
        let suffix = mode == .ai ? "-enhanced_ia" : "-enhanced"
        let buildSuffix = BuildInfo.buildStamp.replacingOccurrences(of: " ", with: "_")
        var candidate = directory.appendingPathComponent("\(baseName)\(suffix)-\(buildSuffix).\(format.fileExtension)")
        var index = 1

        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName)\(suffix)-\(buildSuffix)-\(index).\(format.fileExtension)")
            index += 1
        }

        return candidate
    }

    private func aiTuningSummary(_ tuning: AIEnhancementTuning?) -> String? {
        guard let tuning else { return nil }
        return "sombras \(Int(tuning.shadowAmount * 100)), luces \(Int(tuning.highlightAmount * 100)), vibrance \(Int(tuning.vibrance * 100)), nitidez \(Int(tuning.sharpen * 100))"
    }

    private var proPreviewSummary: String {
        switch effectivePreviewPreset {
        case .portrait:
            let suffix = preset == .auto ? " · AUTO -> \(autoDecisionLabel(for: effectivePreviewScene))" : ""
            return "retrato natural, contraste contenido, color moderado y detalle suave\(suffix)"
        case .landscape:
            let suffix = preset == .auto ? " · AUTO -> \(autoDecisionLabel(for: effectivePreviewScene))" : ""
            return "paisaje equilibrado, color vivo moderado y nitidez local suave\(suffix)"
        case .document:
            let suffix = preset == .auto ? " · AUTO -> \(autoDecisionLabel(for: effectivePreviewScene))" : ""
            return "documento claro, contraste funcional y nitidez para lectura\(suffix)"
        case .ecommerce:
            let suffix = preset == .auto ? " · AUTO -> \(autoDecisionLabel(for: effectivePreviewScene))" : ""
            return "producto limpio, color controlado y microdetalle moderado\(suffix)"
        case .auto:
            return "auto local, correccion general y mejora conservadora · AUTO -> \(autoDecisionLabel(for: effectivePreviewScene))"
        }
    }

    private func autoDecisionLabel(for scene: ImageEnhancer.SceneType?) -> String {
        switch scene {
        case .portrait:
            return "Retrato"
        case .document:
            return "Documento"
        case .landscape:
            return "Paisaje"
        case .ecommerce:
            return "Ecommerce"
        case .darkPhoto:
            return "Foto oscura"
        case .generic, .none:
            return "General"
        }
    }

    private func aiRecipeSummary(_ recipe: EnhancementRecipe) -> String {
        let tuning = recipe.tuning
        let exposureText = String(format: "%.2f", tuning.exposureEV)
        let upscaleText: String
        if let upscale = recipe.upscale, upscale.enabled {
            if let target = upscale.targetLongSide {
                upscaleText = "upscale \(target)px"
            } else {
                upscaleText = "upscale on"
            }
        } else {
            upscaleText = "sin upscale"
        }
        let faceRestoreText: String
        if let faceRestore = recipe.faceRestore, faceRestore.enabled {
            let strength = Int(((faceRestore.strength ?? 0.5) * 100).rounded())
            faceRestoreText = "face restore \(strength)%"
        } else {
            faceRestoreText = "sin face restore"
        }

        return "preset \(recipe.preset), calidad \(Int(recipe.exportQuality * 100))%, sombras \(Int(tuning.shadowAmount * 100)), luces \(Int(tuning.highlightAmount * 100)), vibrance \(Int(tuning.vibrance * 100)), nitidez \(Int(tuning.sharpen * 100)), sat \(Int(tuning.saturation * 100)), exp \(exposureText) EV, \(upscaleText), \(faceRestoreText)"
    }

    private func aiDecisionExplanation(_ recipe: EnhancementRecipe) -> String {
        var components: [String] = []

        if let faceRestore = recipe.faceRestore, faceRestore.enabled {
            let strength = Int(((faceRestore.strength ?? 0.5) * 100).rounded())
            components.append("restauracion facial suave \(strength)%")
        }

        if let upscale = recipe.upscale, upscale.enabled {
            if let target = upscale.targetLongSide {
                components.append("upscale hasta \(target) px")
            } else {
                components.append("upscale activado")
            }
        }

        if components.isEmpty {
            return "La IA ajusta la receta local sin activar modulos extra."
        }

        return "La IA prioriza \(components.joined(separator: " y "))."
    }

    private func aiDecisionHighlights(_ recipe: EnhancementRecipe) -> [String] {
        var highlights: [String] = [
            "preset \(recipe.preset)",
            "salida \(recipe.exportFormat.uppercased())"
        ]

        if let upscale = recipe.upscale, upscale.enabled {
            if let target = upscale.targetLongSide {
                highlights.append("upscale \(target)px")
            } else {
                highlights.append("upscale on")
            }
        }

        if let faceRestore = recipe.faceRestore, faceRestore.enabled {
            let strength = Int(((faceRestore.strength ?? 0.5) * 100).rounded())
            highlights.append("face restore \(strength)%")
        }

        return highlights
    }

    private func aiDecisionLogSummary(for resolution: AIRunResolution) -> String {
        var components: [String] = [
            "preset \(resolution.preset.rawValue)",
            "formato \(resolution.format.rawValue)"
        ]

        if let recipe = resolution.recipe {
            if let upscale = recipe.upscale, upscale.enabled {
                if let target = upscale.targetLongSide {
                    components.append("upscale \(target)px")
                } else {
                    components.append("upscale on")
                }
            }

            if let faceRestore = recipe.faceRestore, faceRestore.enabled {
                let strength = Int(((faceRestore.strength ?? 0.5) * 100).rounded())
                components.append("face restore \(strength)%")
            }
        }

        return components.joined(separator: ", ")
    }
}

private struct PreviewLightboxView: View {
    let items: [PreviewLightboxItem]
    @Binding var selectedKind: PreviewKind

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool
    @State private var zoomScale: CGFloat = 1.0
    @State private var dragOffset: CGSize = .zero
    @State private var accumulatedOffset: CGSize = .zero

    private var selectedIndex: Int {
        items.firstIndex(where: { $0.kind == selectedKind }) ?? 0
    }

    private var selectedItem: PreviewLightboxItem? {
        guard items.indices.contains(selectedIndex) else { return nil }
        return items[selectedIndex]
    }

    var body: some View {
        VStack(spacing: 12) {
            header

            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.92))

                if let item = selectedItem {
                    GeometryReader { geometry in
                        ScrollView([.horizontal, .vertical]) {
                            Image(nsImage: item.image)
                                .resizable()
                                .scaledToFit()
                                .frame(
                                    width: max(geometry.size.width - 80, 320) * zoomScale,
                                    height: max(geometry.size.height - 80, 320) * zoomScale
                                )
                                .offset(
                                    x: accumulatedOffset.width + dragOffset.width,
                                    y: accumulatedOffset.height + dragOffset.height
                                )
                                .gesture(dragGesture)
                                .padding(40)
                        }
                    }
                }
            }
            .frame(minWidth: 900, minHeight: 560)
            .overlay(alignment: .leading) {
                if items.count > 1 {
                    navigationButton(systemImage: "chevron.left", action: goToPrevious)
                        .padding(.leading, 14)
                }
            }
            .overlay(alignment: .trailing) {
                if items.count > 1 {
                    navigationButton(systemImage: "chevron.right", action: goToNext)
                        .padding(.trailing, 14)
                }
            }
        }
        .padding(18)
        .frame(minWidth: 980, minHeight: 680)
        .focusable()
        .focused($isFocused)
        .onAppear {
            isFocused = true
        }
        .onMoveCommand { direction in
            switch direction {
            case .left:
                goToPrevious()
            case .right:
                goToNext()
            default:
                break
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            if let item = selectedItem {
                Text(item.kind.rawValue)
                    .font(.system(size: 17, weight: .bold))

                if let badge = item.badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(badge == "IA" ? Color.purple.opacity(0.14) : Color.blue.opacity(0.12))
                        .foregroundColor(badge == "IA" ? .purple : .blue)
                        .clipShape(Capsule())
                }

                Text("\(selectedIndex + 1)/\(items.count)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                if let summary = item.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Button("1:1") {
                    resetViewport(to: 1.0)
                }
                .buttonStyle(.bordered)

                Button("Ajustar") {
                    resetViewport(to: 0.9)
                }
                .buttonStyle(.bordered)

                Button("Cerrar") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = value.translation
            }
            .onEnded { value in
                accumulatedOffset.width += value.translation.width
                accumulatedOffset.height += value.translation.height
                dragOffset = .zero
            }
    }

    private func navigationButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .bold))
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.borderedProminent)
    }

    private func goToPrevious() {
        guard items.count > 1 else { return }
        let newIndex = selectedIndex == 0 ? items.count - 1 : selectedIndex - 1
        selectedKind = items[newIndex].kind
        resetViewport(to: 1.0)
    }

    private func goToNext() {
        guard items.count > 1 else { return }
        let newIndex = selectedIndex == items.count - 1 ? 0 : selectedIndex + 1
        selectedKind = items[newIndex].kind
        resetViewport(to: 1.0)
    }

    private func resetViewport(to scale: CGFloat) {
        zoomScale = scale
        dragOffset = .zero
        accumulatedOffset = .zero
    }
}
