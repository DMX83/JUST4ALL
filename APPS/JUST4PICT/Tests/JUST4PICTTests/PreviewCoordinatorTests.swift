import XCTest
import AppKit
@testable import JUST4PICT

@MainActor
final class PreviewCoordinatorTests: XCTestCase {
    private func makeCoordinator() -> PreviewCoordinator {
        PreviewCoordinator(
            processor: BatchItemProcessor(
                enhancer: ImageEnhancer(),
                reconstruction: OpenAIImageReconstructionService()
            )
        )
    }

    private func requireSample() throws -> URL {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let candidates = [
            packageRoot.appendingPathComponent("images/images_document_orig.jpeg"),
            packageRoot.appendingPathComponent("images/image_paisaje_orig.jpeg"),
            packageRoot.appendingPathComponent("images/PHOTO-2026-03-18-22-18-19 5.jpg")
        ]
        guard let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw XCTSkip("Muestra de QA no disponible en este entorno")
        }
        return url
    }

    func testPrepareForSelectionLoadsOriginalAndMarksNeedsRefresh() throws {
        let url = try requireSample()
        let state = PreviewStateViewModel()
        let coordinator = makeCoordinator()

        coordinator.prepareForSelection(state: state, files: [url], preset: .auto)

        XCTAssertEqual(state.selectedPreviewURL, url)
        XCTAssertNotNil(state.originalPreviewImage)
        XCTAssertNotNil(state.effectivePreviewScene, "la escena efectiva debe calcularse en la preparación")
        XCTAssertTrue(state.previewNeedsRefresh)
        XCTAssertNil(state.proPreviewImage)
        XCTAssertNil(state.aiPreviewImage)
    }

    func testPrepareWithoutInputsClearsState() throws {
        let state = PreviewStateViewModel()
        state.selectedPreviewURL = nil
        let coordinator = makeCoordinator()

        coordinator.prepareForSelection(state: state, files: [], preset: .auto)

        XCTAssertNil(state.originalPreviewImage)
        XCTAssertNil(state.effectivePreviewScene)
        XCTAssertEqual(state.effectivePreviewPreset, .auto)
    }

    func testScheduleRefreshGeneratesLocalProPreviewAndClearsFlag() async throws {
        let url = try requireSample()
        let state = PreviewStateViewModel()
        let aiState = AIResolutionViewModel()
        let coordinator = makeCoordinator()

        coordinator.prepareForSelection(state: state, files: [url], preset: .auto)
        coordinator.scheduleRefresh(
            state: state,
            aiState: aiState,
            preset: .auto,
            mode: .local,
            log: { _ in }
        )
        await state.previewTask?.value

        XCTAssertFalse(state.isGeneratingPreview)
        XCTAssertNotNil(state.proPreviewImage, "el flujo local debe generar la preview PRO")
        XCTAssertNil(state.aiPreviewImage, "sin tuning IA no debe generarse preview IA")
        XCTAssertFalse(state.previewNeedsRefresh)
    }

    func testInvalidateClearsProcessedPreviewsAndKeepsPendingFlag() async throws {
        let url = try requireSample()
        let state = PreviewStateViewModel()
        let aiState = AIResolutionViewModel()
        let coordinator = makeCoordinator()

        coordinator.prepareForSelection(state: state, files: [url], preset: .auto)
        coordinator.scheduleRefresh(
            state: state,
            aiState: aiState,
            preset: .auto,
            mode: .local,
            log: { _ in }
        )
        await state.previewTask?.value
        XCTAssertNotNil(state.proPreviewImage)

        coordinator.invalidate(state: state, hasPendingInput: true)

        XCTAssertNil(state.proPreviewImage)
        XCTAssertNil(state.aiPreviewImage)
        XCTAssertTrue(state.previewNeedsRefresh)
    }
}
