import Foundation
import AppKit
import SwiftUI

@MainActor
final class PreviewStateViewModel: ObservableObject {
    @Published var selectedPreviewURL: URL?
    @Published var originalPreviewImage: NSImage?
    @Published var proPreviewImage: NSImage?
    @Published var aiPreviewImage: NSImage?
    @Published var isGeneratingPreview = false
    @Published var previewNeedsRefresh = false
    @Published var effectivePreviewPreset: EnhancementPreset = .auto
    @Published var effectivePreviewScene: ImageEnhancer.SceneType?
    @Published var beforeAfterPosition: CGFloat = 0.5

    var previewTask: Task<Void, Never>?
    var previewRequestID = UUID()

    func cancelPreviewTask() {
        previewTask?.cancel()
        previewTask = nil
    }

    func nextPreviewRequestID() -> UUID {
        let requestID = UUID()
        previewRequestID = requestID
        return requestID
    }

    func clearAll() {
        cancelPreviewTask()
        selectedPreviewURL = nil
        originalPreviewImage = nil
        proPreviewImage = nil
        aiPreviewImage = nil
        effectivePreviewScene = nil
        effectivePreviewPreset = .auto
        previewNeedsRefresh = false
        isGeneratingPreview = false
        beforeAfterPosition = 0.5
    }

    func clearProcessedPreview() {
        cancelPreviewTask()
        proPreviewImage = nil
        aiPreviewImage = nil
        previewNeedsRefresh = selectedPreviewURL != nil
    }
}
