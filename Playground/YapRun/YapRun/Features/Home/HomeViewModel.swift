//
//  HomeViewModel.swift
//  YapRun
//
//  State management for the redesigned home screen.
//

#if os(iOS)
import AVFoundation
import Observation
import RunAnywhere
import os

@Observable
@MainActor
final class HomeViewModel {

    // MARK: - Types

    enum MicState: String {
        case unknown, granted, denied

        var icon: String {
            switch self {
            case .unknown: "mic.fill"
            case .granted: "checkmark.circle.fill"
            case .denied:  "xmark.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .unknown: .orange
            case .granted: AppColors.primaryGreen
            case .denied:  AppColors.primaryRed
            }
        }

        var label: String {
            switch self {
            case .unknown: "Not determined"
            case .granted: "Granted"
            case .denied:  "Denied — open Settings to allow"
            }
        }
    }

    // MARK: - State

    var micPermission: MicState = .unknown
    var keyboardReady = false
    var models: [ModelInfo] = []
    var currentSTTModelId: String?
    var downloadProgress: [String: Double] = [:]
    var downloadingIds: Set<String> = []
    var dictationHistory: [DictationEntry] = []
    var showAddModelSheet = false
    var errorMessage: String?

    // MARK: - Private

    private let logger = Logger(subsystem: "com.runanywhere.yaprun", category: "Home")

    // MARK: - Refresh

    func refresh() async {
        // Mic permission
        let status = AVAudioApplication.shared.recordPermission
        switch status {
        case .granted:    micPermission = .granted
        case .denied:     micPermission = .denied
        default:          micPermission = .unknown
        }

        // Keyboard + Full Access
        let hasSessionState = SharedDataBridge.shared.defaults?.string(forKey: SharedConstants.Keys.sessionState) != nil
        keyboardReady = hasSessionState

        // Models
        do {
            let allModels = try await RunAnywhere.availableModels()
            models = allModels.filter { $0.category == .speechRecognition }
        } catch {
            logger.error("Failed to load models: \(error.localizedDescription)")
        }

        // Current STT
        if let current = await RunAnywhere.currentSTTModel {
            currentSTTModelId = current.id
        }

        // History
        loadHistory()
    }

    // MARK: - Mic Permission

    func requestMicPermission() async {
        let granted = await AVAudioApplication.requestRecordPermission()
        micPermission = granted ? .granted : .denied
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Model Management

    func downloadModel(_ modelId: String) async {
        guard !downloadingIds.contains(modelId) else { return }
        downloadingIds.insert(modelId)
        downloadProgress[modelId] = 0

        do {
            let stream = try await RunAnywhere.downloadModel(modelId)
            for await progress in stream {
                downloadProgress[modelId] = progress.overallProgress
                if progress.stage == .completed { break }
            }

            // Auto-load after download
            try await RunAnywhere.loadSTTModel(modelId)
            currentSTTModelId = modelId
            SharedDataBridge.shared.preferredSTTModelId = modelId
            logger.info("Model \(modelId) downloaded and loaded")
        } catch {
            errorMessage = "Download failed: \(error.localizedDescription)"
            logger.error("Download failed for \(modelId): \(error.localizedDescription)")
        }

        downloadingIds.remove(modelId)
        downloadProgress.removeValue(forKey: modelId)

        // Refresh model list to update isDownloaded states
        await refresh()
    }

    func loadModel(_ modelId: String) async {
        do {
            try await RunAnywhere.loadSTTModel(modelId)
            currentSTTModelId = modelId
            SharedDataBridge.shared.preferredSTTModelId = modelId
            logger.info("Model \(modelId) loaded")
        } catch {
            errorMessage = "Failed to load model: \(error.localizedDescription)"
            logger.error("Load failed for \(modelId): \(error.localizedDescription)")
        }
    }

    func deleteModel(_ modelId: String) async {
        guard let model = models.first(where: { $0.id == modelId }) else { return }
        do {
            try await RunAnywhere.deleteStoredModel(modelId, framework: model.framework)
            if currentSTTModelId == modelId {
                currentSTTModelId = nil
            }
            logger.info("Model \(modelId) deleted")
            await refresh()
        } catch {
            errorMessage = "Delete failed: \(error.localizedDescription)"
            logger.error("Delete failed for \(modelId): \(error.localizedDescription)")
        }
    }

    func addModelFromURL(_ urlString: String, name: String) {
        guard let url = URL(string: urlString) else {
            errorMessage = "Invalid URL"
            return
        }
        RunAnywhere.registerModel(
            name: name,
            url: url,
            framework: .onnx,
            modality: .speechRecognition
        )
        logger.info("Registered custom model: \(name) from \(urlString)")
        Task { await refresh() }
    }

    // MARK: - History

    func clearHistory() {
        dictationHistory = []
        SharedDataBridge.shared.defaults?.removeObject(forKey: SharedConstants.Keys.dictationHistory)
    }

    private func loadHistory() {
        guard let data = SharedDataBridge.shared.defaults?.data(forKey: SharedConstants.Keys.dictationHistory),
              let entries = try? JSONDecoder().decode([DictationEntry].self, from: data) else {
            dictationHistory = []
            return
        }
        dictationHistory = entries
    }
}

// MARK: - Helpers

import SwiftUI

extension ModelInfo {
    var sizeLabel: String {
        if let size = downloadSize, size > 0 {
            return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        }
        return "Unknown size"
    }

    var frameworkBadge: String {
        framework.rawValue
    }

    var frameworkColor: Color {
        switch framework {
        case .onnx:             return .orange
        case .llamaCpp:         return .purple
        case .foundationModels: return .blue
        case .coreml:           return .cyan
        default:                return .gray
        }
    }
}

#endif
