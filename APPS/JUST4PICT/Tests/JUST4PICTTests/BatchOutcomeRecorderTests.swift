import XCTest
@testable import JUST4PICT

@MainActor
final class BatchOutcomeRecorderTests: XCTestCase {
    private func makeRecorder() -> BatchOutcomeRecorder {
        let defaults = UserDefaults(suiteName: "j4pict-tests-\(UUID().uuidString)")!
        return BatchOutcomeRecorder(historyStore: PictHistoryStore(defaults: defaults), enhancer: ImageEnhancer())
    }

    private func makeTuning() -> AIEnhancementTuning {
        AIEnhancementTuning(
            shadowAmount: 0.3,
            highlightAmount: 0.8,
            vibrance: 0.15,
            sharpen: 0.3,
            sharpenRadius: 0.5,
            contrast: 1.0,
            saturation: 1.0,
            exposureEV: 0.0
        )
    }

    private func makeResolution(
        preset: EnhancementPreset = .portrait,
        usedFallback: Bool = false,
        recipe: EnhancementRecipe? = nil
    ) -> AIRunResolution {
        AIRunResolution(
            preset: preset,
            format: .png,
            quality: 1.0,
            upscaleTargetLongSide: nil,
            faceRestoreStrength: nil,
            aiSuggestedPreset: "Retrato",
            aiSuggestedQuality: 1.0,
            aiReason: "test",
            aiPrompt: "prompt de prueba",
            aiTuning: nil,
            recipe: recipe,
            usedFallback: usedFallback
        )
    }

    func testRecordSuccessUpdatesBatchHistoryAndActivity() {
        let recorder = makeRecorder()
        let batchState = BatchStateViewModel()
        let input = URL(fileURLWithPath: "/tmp/foto.png")
        batchState.resetForNewRun(inputFiles: [input])
        var logs: [String] = []

        let history = recorder.recordSuccess(
            inputURL: input,
            outputURL: URL(fileURLWithPath: "/tmp/foto-enhanced-x.png"),
            mode: .local,
            sourcePreset: .portrait,
            resolution: makeResolution(),
            totalCount: 1,
            history: [],
            storeFullPrompt: false,
            batchState: batchState,
            log: { logs.append($0) }
        )

        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.inputFileName, "foto.png")
        XCTAssertEqual(history.first?.preset, "Retrato")
        XCTAssertNil(history.first?.effectiveAutoDecision, "sin preset AUTO no hay decisión efectiva")

        guard case .success? = batchState.batchResults[input]?.status else {
            return XCTFail("el resultado debería ser success")
        }
        XCTAssertEqual(batchState.processedCount, 1)
        XCTAssertEqual(batchState.failedCount, 0)
        XCTAssertEqual(batchState.progress, 1.0, accuracy: 0.0001)
        XCTAssertTrue(logs.contains { $0.contains("✅") })
    }

    func testRecordFailureMarksFailedAndLogs() {
        let recorder = makeRecorder()
        let batchState = BatchStateViewModel()
        let input = URL(fileURLWithPath: "/tmp/foto.png")
        batchState.resetForNewRun(inputFiles: [input])
        var logs: [String] = []

        let error = NSError(domain: "tests", code: 1, userInfo: [NSLocalizedDescriptionKey: "boom"])
        recorder.recordFailure(
            inputURL: input,
            mode: .ai,
            error: error,
            totalCount: 1,
            batchState: batchState,
            log: { logs.append($0) }
        )

        guard case .failed? = batchState.batchResults[input]?.status else {
            return XCTFail("el resultado debería ser failed")
        }
        XCTAssertEqual(batchState.failedCount, 1)
        XCTAssertEqual(batchState.processedCount, 0)
        XCTAssertEqual(batchState.batchResults[input]?.errorMessage, "boom")
        XCTAssertTrue(logs.contains { $0.contains("❌") && $0.contains("[IA]") })
    }

    func testAutoDecisionOnlyWithAutoPreset() {
        let recorder = makeRecorder()

        let nonAuto = recorder.autoDecision(
            for: URL(fileURLWithPath: "/tmp/nada.png"),
            sourcePreset: .portrait,
            resolution: makeResolution()
        )
        XCTAssertNil(nonAuto, "sin preset AUTO no se registra decisión efectiva")
    }

    func testAutoDecisionUsesRecipeSceneWhenAvailable() {
        let recorder = makeRecorder()
        let recipe = EnhancementRecipe(
            scene: "retrato",
            objective: "test",
            preset: "Retrato",
            exportFormat: "png",
            exportQuality: 1.0,
            tuning: makeTuning(),
            upscale: nil,
            faceRestore: nil
        )

        let decision = recorder.autoDecision(
            for: URL(fileURLWithPath: "/tmp/nada.png"),
            sourcePreset: .auto,
            resolution: makeResolution(preset: .auto, recipe: recipe)
        )

        XCTAssertEqual(decision, "Retrato")
    }

    func testModeLogPrefixAndTuningSummary() {
        XCTAssertEqual(BatchOutcomeRecorder.modeLogPrefix(.local), "[PRO]")
        XCTAssertEqual(BatchOutcomeRecorder.modeLogPrefix(.ai), "[IA]")
        XCTAssertEqual(BatchOutcomeRecorder.modeLogPrefix(.reconstructAI), "[IA-R]")

        XCTAssertNil(BatchOutcomeRecorder.aiTuningSummary(nil))
        let summary = BatchOutcomeRecorder.aiTuningSummary(makeTuning())
        XCTAssertEqual(summary, "sombras 30, luces 80, vibrance 15, nitidez 30")
    }
}
