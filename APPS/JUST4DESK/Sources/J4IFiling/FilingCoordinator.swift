import Foundation
import J4ICore
import J4IDocs
import J4IAI
import J4IIndex

/// Orquesta el pipeline de archivado: análisis → clasificación → plan → ejecución + journal.
///
/// Contratos:
/// - Nunca borra: solo mueve (con undo por journal).
/// - Cache por hash: no se re-analiza ni re-clasifica un documento ya visto.
/// - Duplicados (mismo hash ya archivado y presente): se dejan en origen (acción `skipped-duplicate`).
/// - IA no bloquea: si falla o no hay clave, caen las reglas locales; si tampoco hay match → cuarentena.
public final class FilingCoordinator: @unchecked Sendable {
    public struct Outcome: Sendable, Equatable {
        public let sourcePath: String
        public let destinationPath: String
        public let categoryPath: String
        public let action: String   // move | quarantine | simulate | skipped-duplicate | error
        public let reason: String
    }

    public var simulationMode: Bool
    public var aiEnabled: Bool

    private let index: SearchIndex
    private let rootURL: URL
    private let executor: FilingExecutor
    private let advisor: DeepSeekFilingAdvisor?
    private let knowledge: LocalKnowledgeStore

    public init(index: SearchIndex, rootURL: URL, simulationMode: Bool = false, advisor: DeepSeekFilingAdvisor? = nil, knowledge: LocalKnowledgeStore = .shared) {
        self.index = index
        self.rootURL = rootURL
        self.executor = FilingExecutor(rootURL: rootURL)
        self.simulationMode = simulationMode
        self.advisor = advisor
        self.knowledge = knowledge
        self.aiEnabled = advisor != nil
    }

    public func processFile(at url: URL, batchID: String? = nil) async -> Outcome {
        let standardized = url.standardizedFileURL
        let displayName = standardized.lastPathComponent
        J4Log.info(.filing, "Procesando «\(displayName)»…")
        do {
            let computedHash = await Task.detached(priority: .utility) { DocumentAnalyzer.sha256Hex(of: standardized) }.value
            guard let hash = computedHash else {
                J4Log.error(.filing, "No se pudo calcular el hash de «\(displayName)» (¿fichero ilegible?).")
                return Outcome(sourcePath: standardized.path, destinationPath: "", categoryPath: "", action: "error", reason: "No se pudo leer el fichero.")
            }
            J4Log.debug(.filing, "Hash de «\(displayName)»: \(hash.prefix(12))…")

            let cachedAnalysis: CachedAnalysis? = try? await index.loadCachedAnalysis(hash: hash)

            if let filedPath = cachedAnalysis?.filedPath,
               !filedPath.isEmpty,
               FileManager.default.fileExists(atPath: filedPath) {
                let category = Self.categoryPath(for: filedPath, under: rootURL.path)
                J4Log.info(.filing, "Duplicado: «\(displayName)» ya está archivado en «\(category)»; se deja en origen.")
                return Outcome(
                    sourcePath: standardized.path,
                    destinationPath: filedPath,
                    categoryPath: category,
                    action: "skipped-duplicate",
                    reason: "Duplicado de un documento ya archivado."
                )
            }

            let profile: DocumentProfile
            if let json = cachedAnalysis?.profileJSON,
               let decoded = try? JSONDecoder().decode(DocumentProfile.self, from: Data(json.utf8)) {
                profile = decoded
                J4Log.debug(.filing, "Usando análisis en caché de «\(displayName)».")
            } else {
                let analyzed = await Task.detached(priority: .utility) { DocumentAnalyzer.analyze(url: standardized) }.value
                guard let analyzed else {
                    J4Log.error(.filing, "No se pudo leer «\(displayName)» para analizarlo (¿permisos o fichero bloqueado?).")
                    return Outcome(sourcePath: standardized.path, destinationPath: "", categoryPath: "", action: "error", reason: "No se pudo analizar el documento.")
                }
                profile = analyzed
                J4Log.debug(.filing, "Analizado «\(displayName)»: \(analyzed.textLength) caracteres, páginas: \(analyzed.pageCount.map { String($0) } ?? "-"), OCR: \(analyzed.usedOCR ? "sí" : "no").")
            }

            var proposal: FilingProposal?
            if let json = cachedAnalysis?.proposalJSON,
               let decoded = try? JSONDecoder().decode(FilingProposal.self, from: Data(json.utf8)) {
                proposal = decoded
                J4Log.debug(.filing, "Propuesta en caché para «\(displayName)»: \(decoded.categoryPath) (fuente: \(decoded.source.rawValue)).")
            }
            // Conocimiento local (F12.0): extensión ya aprendida → sin llamar a la IA.
            if proposal == nil,
               let ext = KnowledgeFeatures.fileExtension(ofName: profile.fileName),
               let rule = knowledge.promotedRule(kind: .fileExtension, value: ext) {
                proposal = FilingProposal(
                    categoryPath: rule.categoryPath,
                    confidence: rule.confidence,
                    reason: "conocimiento local: extensión «.\(ext)» (\(rule.observations) observaciones)",
                    source: .knowledge
                )
                knowledge.registerHit()
                J4Log.info(.filing, "Conocimiento local (sin IA) → «\(rule.categoryPath)» para «\(displayName)» (ext .\(ext)).")
            }
            if proposal == nil {
                if aiEnabled, let advisor {
                    if AIControlCenter.shared.canUseAI() {
                        AIControlCenter.shared.registerCall()
                        do {
                            proposal = try await advisor.suggest(profile: profile, allowedCategories: TaxonomyInventory.availableDestinations(rootURL: rootURL))
                            if let aiProposal = proposal {
                                J4Log.info(.ai, "IA → «\(aiProposal.categoryPath)» (confianza \(String(format: "%.2f", aiProposal.confidence))): \(aiProposal.reason)")
                                // Aprendizaje (F12.0): la respuesta de la IA alimenta el conocimiento local.
                                recordKnowledge(kind: .fileExtension, value: KnowledgeFeatures.fileExtension(ofName: profile.fileName), categoryPath: aiProposal.categoryPath, confidence: aiProposal.confidence)
                            }
                        } catch {
                            J4Log.warn(.ai, "La IA falló para «\(displayName)» (\(error.localizedDescription)); se usan las reglas locales.")
                        }
                    } else {
                        let usage = AIControlCenter.shared.usage()
                        J4Log.warn(.ai, "IA omitida para «\(displayName)»: desactivada o cap diario alcanzado (\(usage.callsToday)/\(usage.dailyLimit)).")
                    }
                }
                if proposal == nil {
                    proposal = RulesFilingClassifier.classify(fileName: profile.fileName, textSample: profile.textSample)
                    if let rulesProposal = proposal {
                        J4Log.info(.filing, "Reglas locales → «\(rulesProposal.categoryPath)» (confianza \(String(format: "%.2f", rulesProposal.confidence))): \(rulesProposal.reason)")
                    }
                }
                if proposal == nil, let byExtension = RulesFilingClassifier.classifyByExtension(fileName: profile.fileName) {
                    proposal = byExtension
                    J4Log.info(.filing, "Por extensión → «\(byExtension.categoryPath)» (\(byExtension.reason))")
                }
                if proposal == nil {
                    J4Log.warn(.filing, "Sin coincidencias para «\(displayName)»: se enviará a cuarentena.")
                }
            }

            let plan = FilingPlanner.resolve(proposal: proposal, originalFileName: profile.fileName, categories: TaxonomyInventory.categories(rootURL: rootURL))
            J4Log.debug(.filing, "Plan para «\(displayName)»: \(plan.categoryRelativePath)/\(plan.fileName) (fuente: \(plan.source.rawValue), confianza \(String(format: "%.2f", plan.confidence))).")
            let batchID = batchID ?? UUID().uuidString

            if simulationMode {
                let simulated = rootURL
                    .appendingPathComponent(plan.categoryRelativePath, isDirectory: true)
                    .appendingPathComponent(plan.fileName)
                J4Log.info(.filing, "[SIMULACIÓN] «\(displayName)» → «\(plan.categoryRelativePath)/\(plan.fileName)».")
                _ = try? await index.journalAppend(
                    batchID: batchID,
                    sourcePath: standardized.path,
                    destinationPath: simulated.path,
                    categoryPath: plan.categoryRelativePath,
                    action: "simulate"
                )
                await storeCache(hash: profile.contentHash, profile: profile, proposal: proposal)
                return Outcome(
                    sourcePath: standardized.path,
                    destinationPath: simulated.path,
                    categoryPath: plan.categoryRelativePath,
                    action: "simulate",
                    reason: plan.reason
                )
            }

            let result = try executor.execute(plan: plan, sourceURL: standardized)
            let action = plan.isQuarantine ? "quarantine" : "move"
            if result.destinationURL.lastPathComponent != plan.fileName {
                J4Log.info(.filing, "Colisión de nombre: «\(plan.fileName)» → «\(result.destinationURL.lastPathComponent)».")
            }
            if plan.isQuarantine {
                J4Log.warn(.filing, "Cuarentena: «\(displayName)» → «\(result.categoryRelativePath)» (\(plan.reason))")
            } else {
                J4Log.info(.filing, "Archivado: «\(displayName)» → «\(result.categoryRelativePath)/\(result.destinationURL.lastPathComponent)» (\(plan.source.rawValue), confianza \(String(format: "%.2f", plan.confidence))).")
            }
            _ = try? await index.journalAppend(
                batchID: batchID,
                sourcePath: standardized.path,
                destinationPath: result.destinationURL.path,
                categoryPath: result.categoryRelativePath,
                action: action
            )
            await storeCache(hash: profile.contentHash, profile: profile, proposal: proposal)
            try? await index.updateCachedFiledPath(hash: profile.contentHash, filedPath: result.destinationURL.path)
            await indexFiledDocument(at: result.destinationURL)

            return Outcome(
                sourcePath: standardized.path,
                destinationPath: result.destinationURL.path,
                categoryPath: result.categoryRelativePath,
                action: action,
                reason: plan.reason
            )
        } catch {
            J4Log.error(.filing, "Error procesando «\(displayName)»: \(error.localizedDescription)")
            return Outcome(sourcePath: standardized.path, destinationPath: "", categoryPath: "", action: "error", reason: error.localizedDescription)
        }
    }

    /// Procesa una **unidad** de la carpeta de entrada: fichero suelto → archivado por documento;
    /// carpeta → archivado de la carpeta completa (con todo su contenido).
    public func processItem(at url: URL) async -> Outcome {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        if isDirectory.boolValue {
            return await processFolder(at: url)
        }
        return await processFile(at: url)
    }

    /// Propuesta de destino SIN mover nada (para «Por revisar» y el Explorador): mismo criterio y
    /// salvaguardas que el archivado (IA → reglas → extensión dominante; umbral → cuarentena) y
    /// respetando el control de IA (interruptor + cap diario). Consulta fresca: no usa caché.
    public struct Suggestion: Sendable, Equatable {
        public let sourcePath: String
        public let name: String
        public let categoryPath: String
        public let confidence: Double
        public let source: FilingProposalSource
        public let reason: String
        public let isQuarantine: Bool
        /// Estrategia para carpetas: `split` = cajón heterogéneo → desglosar por ficheros.
        public let folderStrategy: FolderFilingStrategy?

        public init(
            sourcePath: String,
            name: String,
            categoryPath: String,
            confidence: Double,
            source: FilingProposalSource,
            reason: String,
            isQuarantine: Bool,
            folderStrategy: FolderFilingStrategy? = nil
        ) {
            self.sourcePath = sourcePath
            self.name = name
            self.categoryPath = categoryPath
            self.confidence = confidence
            self.source = source
            self.reason = reason
            self.isQuarantine = isQuarantine
            self.folderStrategy = folderStrategy
        }
    }

    public func proposeDestination(for url: URL) async -> Suggestion? {
        let standardized = url.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDirectory) else { return nil }
        let displayName = standardized.lastPathComponent
        let isFolder = isDirectory.boolValue

        let profile: DocumentProfile
        let folderSummary: FolderContentSummary?
        if isFolder {
            let summary = await Task.detached(priority: .utility) { FolderProfiler.summarize(folderURL: standardized) }.value
            folderSummary = summary
            let summaryText = FolderProfiler.summaryText(folderName: displayName, summary: summary)
            profile = DocumentProfile(
                fileName: displayName,
                fileExtension: "",
                fileSizeBytes: summary.totalBytes,
                contentHash: "folder:\(displayName):\(summary.totalBytes):\(summary.fileCount)",
                hasTextLayer: !summary.textSample.isEmpty,
                usedOCR: false,
                pageCount: nil,
                textLength: summaryText.count,
                textSample: summaryText,
                dates: [],
                amounts: [],
                identifiers: [],
                analyzedAt: Date()
            )
        } else {
            folderSummary = nil
            guard let analyzed = await Task.detached(priority: .utility, operation: { DocumentAnalyzer.analyze(url: standardized) }).value else {
                return nil
            }
            profile = analyzed
        }

        var proposal: FilingProposal?
        if aiEnabled, let advisor {
            if AIControlCenter.shared.canUseAI() {
                AIControlCenter.shared.registerCall()
                do {
                    proposal = try await advisor.suggest(profile: profile, allowedCategories: TaxonomyInventory.availableDestinations(rootURL: rootURL))
                    if let aiProposal = proposal {
                        J4Log.info(.ai, "IA (sugerencia) → «\(aiProposal.categoryPath)» (confianza \(String(format: "%.2f", aiProposal.confidence))): \(aiProposal.reason)")
                    }
                } catch {
                    J4Log.warn(.ai, "La IA falló al sugerir para «\(displayName)» (\(error.localizedDescription)).")
                }
            } else {
                let usage = AIControlCenter.shared.usage()
                J4Log.warn(.ai, "IA omitida al sugerir «\(displayName)»: desactivada o cap diario alcanzado (\(usage.callsToday)/\(usage.dailyLimit)).")
            }
        }
        if proposal == nil {
            proposal = isFolder
                ? RulesFilingClassifier.classifyFolder(name: displayName, dominantExtension: folderSummary?.dominantExtension)
                : RulesFilingClassifier.classify(fileName: profile.fileName, textSample: profile.textSample)
        }
        if proposal == nil, !isFolder, let byExtension = RulesFilingClassifier.classifyByExtension(fileName: profile.fileName) {
            proposal = byExtension
        }
        if proposal == nil, isFolder, let dominant = folderSummary?.dominantExtension {
            proposal = RulesFilingClassifier.classifyByExtension(fileName: "\(displayName).\(dominant)")
        }

        let isSplit = isFolder && proposal?.folderStrategy == .split
        let plan = FilingPlanner.resolve(proposal: proposal, originalFileName: displayName, categories: TaxonomyInventory.categories(rootURL: rootURL))
        return Suggestion(
            sourcePath: standardized.path,
            name: displayName,
            categoryPath: isSplit ? "" : plan.categoryRelativePath,
            confidence: isSplit ? (proposal?.confidence ?? plan.confidence) : plan.confidence,
            source: plan.source,
            reason: isSplit ? (proposal?.reason ?? plan.reason) : plan.reason,
            isQuarantine: isSplit ? false : plan.isQuarantine,
            folderStrategy: proposal?.folderStrategy
        )
    }

    /// Archiva una carpeta como **unidad completa**: se perfila su contenido (extensión
    /// dominante + muestras de nombres y texto), se clasifica con IA/reglas y se mueve ENTERA
    /// a la categoría, conservando su nombre y su estructura originales.
    ///
    /// Salvaguardas: no se renombra la carpeta, no se descompone su contenido y jamás se borra
    /// (mover + journal + undo, igual que los ficheros). Sin coincidencia → cuarentena.
    public func processFolder(at url: URL, splitDepth: Int = 0, batchID: String? = nil) async -> Outcome {
        let standardized = url.standardizedFileURL
        let displayName = standardized.lastPathComponent
        let batchID = batchID ?? UUID().uuidString
        J4Log.info(.filing, "Procesando carpeta «\(displayName)» como unidad…")

        let summary = await Task.detached(priority: .utility) { FolderProfiler.summarize(folderURL: standardized) }.value
        if summary.isEmpty {
            let subfolders = summary.directoryCount > 0 ? " (\(summary.directoryCount) subcarpeta(s) sin ficheros)" : ""
            J4Log.warn(.filing, "Carpeta sin ficheros «\(displayName)»\(subfolders): se deja en origen (nada que archivar).")
            return Outcome(sourcePath: standardized.path, destinationPath: "", categoryPath: "", action: "skipped-empty", reason: "Carpeta sin ficheros.")
        }
        J4Log.debug(.filing, "Perfil de «\(displayName)»: \(summary.fileCount) fichero(s), extensión dominante «\(summary.dominantExtension ?? "-")».")

        let summaryText = FolderProfiler.summaryText(folderName: displayName, summary: summary)
        let profile = DocumentProfile(
            fileName: displayName,
            fileExtension: "",
            fileSizeBytes: summary.totalBytes,
            contentHash: "folder:\(displayName):\(summary.totalBytes):\(summary.fileCount)",
            hasTextLayer: !summary.textSample.isEmpty,
            usedOCR: false,
            pageCount: nil,
            textLength: summaryText.count,
            textSample: summaryText,
            dates: [],
            amounts: [],
            identifiers: [],
            analyzedAt: Date()
        )

        var proposal: FilingProposal?
        // Conocimiento local (F12.0): palabra del nombre de carpeta ya aprendida → sin IA.
        if let token = KnowledgeFeatures.folderTokens(fromName: displayName).first(where: { knowledge.promotedRule(kind: .folderToken, value: $0) != nil }),
           let rule = knowledge.promotedRule(kind: .folderToken, value: token) {
            proposal = FilingProposal(
                categoryPath: rule.categoryPath,
                confidence: rule.confidence,
                reason: "conocimiento local: «\(token)» en el nombre (\(rule.observations) observaciones)",
                source: .knowledge
            )
            knowledge.registerHit()
            J4Log.info(.filing, "Conocimiento local (sin IA) → «\(rule.categoryPath)» para la carpeta «\(displayName)» (token «\(token)»).")
        }
        if aiEnabled, let advisor {
            if AIControlCenter.shared.canUseAI() {
                AIControlCenter.shared.registerCall()
                do {
                    proposal = try await advisor.suggest(profile: profile, allowedCategories: TaxonomyInventory.availableDestinations(rootURL: rootURL))
                    if let aiProposal = proposal {
                        J4Log.info(.ai, "IA → «\(aiProposal.categoryPath)» (confianza \(String(format: "%.2f", aiProposal.confidence))): \(aiProposal.reason)")
                        if aiProposal.folderStrategy != .split {
                            // Aprendizaje (F12.0): tokens del nombre → categoría (un cajón no enseña categoría).
                            recordKnowledgeTokens(forFolderName: displayName, categoryPath: aiProposal.categoryPath, confidence: aiProposal.confidence)
                        }
                    }
                } catch {
                    J4Log.warn(.ai, "La IA falló para la carpeta «\(displayName)» (\(error.localizedDescription)); se usan las reglas locales.")
                }
            } else {
                let usage = AIControlCenter.shared.usage()
                J4Log.warn(.ai, "IA omitida para la carpeta «\(displayName)»: desactivada o cap diario alcanzado (\(usage.callsToday)/\(usage.dailyLimit)).")
            }
        }
        // Estrategia decidida por la IA (F10.0): cajón heterogéneo → desglosar por ficheros.
        if let aiProposal = proposal, aiProposal.folderStrategy == .split {
            if aiProposal.confidence >= 0.6, summary.fileCount <= Self.maxSplitElements, splitDepth < Self.maxSplitDepth {
                J4Log.info(.filing, "IA decide desglosar «\(displayName)» (\(summary.fileCount) fichero(s)): \(aiProposal.reason)")
                return await processFolderSplit(at: standardized, depth: splitDepth, batchID: batchID)
            }
            J4Log.warn(.filing, "Desglose IA de «\(displayName)» no aplicado (confianza \(String(format: "%.2f", aiProposal.confidence)), \(summary.fileCount) fichero(s), profundidad \(splitDepth)): se archiva como unidad.")
        }
        if proposal == nil {
            proposal = RulesFilingClassifier.classifyFolder(name: displayName, dominantExtension: summary.dominantExtension)
            if let rulesProposal = proposal {
                J4Log.info(.filing, "Reglas locales (nombre/extensión dominante) → «\(rulesProposal.categoryPath)» (confianza \(String(format: "%.2f", rulesProposal.confidence))): \(rulesProposal.reason)")
            }
        }
        if proposal == nil {
            J4Log.warn(.filing, "Sin coincidencias para la carpeta «\(displayName)»: se enviará a cuarentena.")
        }

        let base = FilingPlanner.resolve(proposal: proposal, originalFileName: displayName, categories: TaxonomyInventory.categories(rootURL: rootURL))
        // La carpeta conserva su nombre original (sin plantilla ni saneado): dentro puede haber
        // estructura (apps portables, subtítulos, subtrees propias) que debe viajar intacta.
        let plan = FilingPlan(
            categoryRelativePath: base.categoryRelativePath,
            fileName: displayName,
            confidence: base.confidence,
            reason: base.reason,
            source: base.source
        )

        if simulationMode {
            let simulated = rootURL
                .appendingPathComponent(plan.categoryRelativePath, isDirectory: true)
                .appendingPathComponent(plan.fileName)
            J4Log.info(.filing, "[SIMULACIÓN] carpeta «\(displayName)» → «\(plan.categoryRelativePath)/\(plan.fileName)».")
            _ = try? await index.journalAppend(
                batchID: batchID,
                sourcePath: standardized.path,
                destinationPath: simulated.path,
                categoryPath: plan.categoryRelativePath,
                action: "simulate"
            )
            return Outcome(
                sourcePath: standardized.path,
                destinationPath: simulated.path,
                categoryPath: plan.categoryRelativePath,
                action: "simulate",
                reason: plan.reason
            )
        }

        do {
            let result = try executor.execute(plan: plan, sourceURL: standardized)
            let action = plan.isQuarantine ? "quarantine" : "move"
            if result.destinationURL.lastPathComponent != displayName {
                J4Log.info(.filing, "Colisión de nombre: «\(displayName)» → «\(result.destinationURL.lastPathComponent)».")
            }
            if plan.isQuarantine {
                J4Log.warn(.filing, "Cuarentena (carpeta): «\(displayName)» → «\(result.categoryRelativePath)» (\(plan.reason))")
            } else {
                J4Log.info(.filing, "Archivada carpeta: «\(displayName)» → «\(result.categoryRelativePath)/\(result.destinationURL.lastPathComponent)» (\(plan.source.rawValue), confianza \(String(format: "%.2f", plan.confidence))).")
            }
            _ = try? await index.journalAppend(
                batchID: batchID,
                sourcePath: standardized.path,
                destinationPath: result.destinationURL.path,
                categoryPath: result.categoryRelativePath,
                action: action
            )
            if let root = try? await index.rootID(containing: standardized.path) {
                _ = try? await index.removeEntries(rootID: root.id, paths: [standardized.path])
            }
            await indexFiledFolder(at: result.destinationURL, summaryText: summaryText)
            return Outcome(
                sourcePath: standardized.path,
                destinationPath: result.destinationURL.path,
                categoryPath: result.categoryRelativePath,
                action: action,
                reason: plan.reason
            )
        } catch {
            J4Log.error(.filing, "Error procesando la carpeta «\(displayName)»: \(error.localizedDescription)")
            return Outcome(sourcePath: standardized.path, destinationPath: "", categoryPath: "", action: "error", reason: error.localizedDescription)
        }
    }

    /// Tope de elementos para aplicar un desglose decidido por la IA sin revisión previa.
    static let maxSplitElements = 500
    /// Profundidad máxima de desgloses encadenados (barandilla contra árboles patológicos/enlaces).
    static let maxSplitDepth = 4

    /// Desglosa una carpeta-cajón a petición explícita del usuario («Por revisar»): procesa cada
    /// hijo directo como unidad (ficheros por separado; subcarpetas con su lógica completa) y deja
    /// la cáscara vacía en origen (nunca se borra). Todo va al journal con el MISMO lote de undo.
    public func splitFolder(at url: URL) async -> Outcome {
        await processFolderSplit(at: url, depth: 0, batchID: UUID().uuidString)
    }

    private func processFolderSplit(at url: URL, depth: Int, batchID: String) async -> Outcome {
        let standardized = url.standardizedFileURL
        let displayName = standardized.lastPathComponent
        J4Log.info(.filing, "Desglosando carpeta «\(displayName)» por ficheros…")

        let fileManager = FileManager.default
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        let children = ((try? fileManager.contentsOfDirectory(
            at: standardized,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )) ?? []).sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !children.isEmpty else {
            J4Log.warn(.filing, "Desglose de «\(displayName)»: sin elementos visibles; se deja como está.")
            return Outcome(sourcePath: standardized.path, destinationPath: "", categoryPath: "", action: "skipped-empty", reason: "Carpeta sin elementos.")
        }

        var moved = 0
        var quarantined = 0
        var skipped = 0
        var failures = 0
        var detail: String?
        for child in children {
            let values = try? child.resourceValues(forKeys: keys)
            let isLink = values?.isSymbolicLink == true
            let outcome: Outcome
            if values?.isDirectory == true, !isLink {
                // Subcarpetas: misma lógica de unidad (la IA puede volver a decidir entera/desglosada).
                outcome = await processFolder(at: child, splitDepth: depth + 1, batchID: batchID)
            } else {
                // Ficheros (y enlaces): clasificación individual como cualquier documento.
                outcome = await processFile(at: child, batchID: batchID)
            }
            switch outcome.action {
            case "move":
                moved += 1
                if detail == nil {
                    detail = "«\(child.lastPathComponent)» → \(outcome.categoryPath)"
                }
            case "quarantine":
                quarantined += 1
            case "skipped-duplicate", "skipped-empty", "simulate":
                skipped += 1
            default:
                failures += 1
            }
        }

        var reason = "Desglosada: \(moved) archivado(s), \(quarantined) a cuarentena"
        if skipped > 0 { reason += ", \(skipped) omitido(s)" }
        if failures > 0 { reason += ", \(failures) con error" }
        reason += "."
        if let detail { reason += " Ej.: \(detail)" }
        J4Log.info(.filing, "Desglose de «\(displayName)» → \(reason)")
        if quarantined > 0 {
            J4Log.warn(.filing, "Desglose de «\(displayName)»: \(quarantined) elemento(s) sin destino quedaron en la cuarentena para revisar.")
        }
        return Outcome(sourcePath: standardized.path, destinationPath: "", categoryPath: "", action: "split", reason: reason)
    }

    // MARK: - Conocimiento local (F12.0)

    /// Registra una observación en la base de conocimiento local y deja traza si la regla
    /// acaba de promocionarse (a partir de ahí, las unidades así se clasifican sin IA).
    private func recordKnowledge(kind: LocalKnowledgeStore.FeatureKind, value: String?, categoryPath: String, confidence: Double, fromUser: Bool = false) {
        guard let value, !value.isEmpty else { return }
        let promoted = knowledge.record(kind: kind, value: value, categoryPath: categoryPath, confidence: confidence, fromUser: fromUser)
        if promoted {
            J4Log.info(.filing, "Conocimiento local: regla promovida (\(kind.rawValue) «\(value)» → «\(categoryPath)»); las próximas unidades así se clasificarán sin IA.")
        }
    }

    private func recordKnowledgeTokens(forFolderName name: String, categoryPath: String, confidence: Double, fromUser: Bool = false) {
        for token in KnowledgeFeatures.folderTokens(fromName: name).prefix(3) {
            recordKnowledge(kind: .folderToken, value: token, categoryPath: categoryPath, confidence: confidence, fromUser: fromUser)
        }
    }

    /// Reclasifica manualmente un fichero (p. ej. desde la cuarentena) hacia una categoría del árbol.
    ///
    /// Acción manual y explícita del usuario: no pasa por el modo simulación. Mantiene las garantías
    /// del archivado (mkdirs, colisión `-1`/`-2`, nunca sobreescribe) y queda en el journal (undo).
    public func reclassify(fileAt sourceURL: URL, to categoryRelativePath: String) async -> Outcome {
        let standardized = sourceURL.standardizedFileURL
        let displayName = standardized.lastPathComponent
        var cachedText: String?
        if let entryID = try? await index.entryID(path: standardized.path) {
            cachedText = try? await index.documentText(entryID: entryID)
        }
        do {
            let result = try executor.move(sourceURL: standardized, to: categoryRelativePath)
            if result.destinationURL.lastPathComponent != displayName {
                J4Log.info(.filing, "Colisión de nombre en revisión: «\(displayName)» → «\(result.destinationURL.lastPathComponent)».")
            }
            _ = try? await index.journalAppend(
                batchID: UUID().uuidString,
                sourcePath: standardized.path,
                destinationPath: result.destinationURL.path,
                categoryPath: result.categoryRelativePath,
                action: "move"
            )
            if let root = try? await index.rootID(containing: standardized.path) {
                _ = try? await index.removeEntries(rootID: root.id, paths: [standardized.path])
            }
            await indexFiledDocument(at: result.destinationURL, cachedText: cachedText)
            let hash = await Task.detached(priority: .utility) { DocumentAnalyzer.sha256Hex(of: result.destinationURL) }.value
            if let hash {
                try? await index.updateCachedFiledPath(hash: hash, filedPath: result.destinationURL.path)
            }
            // Aprendizaje (F12.0): una corrección manual del usuario manda y reescribe la regla local.
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: result.destinationURL.path, isDirectory: &isDirectory)
            if isDirectory.boolValue {
                recordKnowledgeTokens(forFolderName: displayName, categoryPath: result.categoryRelativePath, confidence: 1.0, fromUser: true)
            } else {
                recordKnowledge(kind: .fileExtension, value: KnowledgeFeatures.fileExtension(ofName: displayName), categoryPath: result.categoryRelativePath, confidence: 1.0, fromUser: true)
            }
            J4Log.info(.filing, "Revisión: «\(displayName)» → «\(result.categoryRelativePath)/\(result.destinationURL.lastPathComponent)» (manual, desde cuarentena).")
            return Outcome(
                sourcePath: standardized.path,
                destinationPath: result.destinationURL.path,
                categoryPath: result.categoryRelativePath,
                action: "move",
                reason: "Reclasificación manual desde la revisión de cuarentena."
            )
        } catch {
            J4Log.error(.filing, "Error al reclasificar «\(displayName)»: \(error.localizedDescription)")
            return Outcome(sourcePath: standardized.path, destinationPath: "", categoryPath: "", action: "error", reason: error.localizedDescription)
        }
    }

    /// Deshace una entrada del journal (solo acciones `move`/`quarantine` aplicadas).
    public func undo(entry: JournalEntry) async -> Bool {
        guard entry.isUndoable else { return false }
        do {
            try executor.undo(
                destinationURL: URL(fileURLWithPath: entry.destinationPath),
                originalURL: URL(fileURLWithPath: entry.sourcePath)
            )
            try? await index.journalMarkUndone(id: entry.id)
            J4Log.info(.filing, "Deshecho: «\((entry.destinationPath as NSString).lastPathComponent)» vuelve a «\((entry.sourcePath as NSString).abbreviatingWithTildeInPath)».")
            return true
        } catch {
            J4Log.warn(.filing, "No se pudo deshacer «\((entry.destinationPath as NSString).lastPathComponent)»: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Privados

    private func storeCache(hash: String, profile: DocumentProfile, proposal: FilingProposal?) async {
        let encoder = JSONEncoder()
        let profileJSON = (try? encoder.encode(profile)).flatMap { String(data: $0, encoding: .utf8) }
        let proposalJSON = proposal.flatMap { try? encoder.encode($0) }.flatMap { String(data: $0, encoding: .utf8) }
        try? await index.storeCachedAnalysis(hash: hash, profileJSON: profileJSON, proposalJSON: proposalJSON)
    }

    /// Asegura que el documento archivado queda en el índice (entrada + texto para búsqueda por contenido).
    /// `cachedText` permite reutilizar el texto ya extraído (p. ej. al reclasificar desde cuarentena)
    /// y evitar una re-extracción/OCR.
    private func indexFiledDocument(at url: URL, cachedText: String? = nil) async {
        let rootInfo = try? await index.rootID(containing: url.path)
        guard let root = rootInfo else { return }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let write = IndexEntryWrite(
            url: url,
            isDirectory: false,
            sizeBytes: Int64(values?.fileSize ?? 0),
            modifiedAt: values?.contentModificationDate
        )
        _ = try? await index.upsertEntries(rootID: root.id, [write])

        let entryID = try? await index.entryID(path: url.path)
        guard let id = entryID else { return }
        if let cachedText, !cachedText.isEmpty {
            try? await index.setDocumentText(entryID: id, text: cachedText)
            J4Log.debug(.filing, "Texto reutilizado para «\(url.lastPathComponent)» (\(cachedText.count) caracteres).")
            return
        }
        let text = await Task.detached(priority: .utility) { DocumentAnalyzer.extractedText(from: url) }.value
        if let text, !text.isEmpty {
            try? await index.setDocumentText(entryID: id, text: text)
            J4Log.debug(.filing, "Texto indexado para «\(url.lastPathComponent)» (\(text.count) caracteres).")
        }
    }

    /// Índice para una carpeta archivada: entrada de directorio + texto-resumen (buscable por
    /// contenido). El detalle del árbol lo indexa la vigilancia del root destino al detectar
    /// el directorio nuevo (escaneo de subárbol).
    private func indexFiledFolder(at url: URL, summaryText: String) async {
        guard let rootInfo = try? await index.rootID(containing: url.path) else { return }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let write = IndexEntryWrite(
            url: url,
            isDirectory: true,
            sizeBytes: Int64(values?.fileSize ?? 0),
            modifiedAt: values?.contentModificationDate
        )
        _ = try? await index.upsertEntries(rootID: rootInfo.id, [write])
        guard let entryID = try? await index.entryID(path: url.path), !summaryText.isEmpty else { return }
        try? await index.setDocumentText(entryID: entryID, text: summaryText)
        J4Log.debug(.filing, "Texto-resumen indexado para la carpeta «\(url.lastPathComponent)» (\(summaryText.count) caracteres).")
    }

    static func categoryPath(for filedPath: String, under rootPath: String) -> String {
        let root = rootPath.hasSuffix("/") ? String(rootPath.dropLast()) : rootPath
        guard filedPath.hasPrefix(root + "/") else { return "" }
        let relative = String(filedPath.dropFirst(root.count + 1))
        let directory = (relative as NSString).deletingLastPathComponent
        return directory.isEmpty ? DefaultTaxonomy.quarantineRelativePath : directory
    }
}
