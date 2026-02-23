//
//  HomeViewModel.swift
//  YapRun
//
//  State management for the home screen.
//  Shared between iOS and macOS with targeted #if os() for platform-specific APIs.
//

import AVFoundation
import Observation
import RunAnywhere
import SwiftUI
import os

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@Observable
@MainActor
final class HomeViewModel {

    // MARK: - State

    var micPermission: MicPermissionState = .unknown
    var models: [ModelInfo] = []
    var currentSTTModelId: String?
    var downloadProgress: [String: Double] = [:]
    var downloadingIds: Set<String> = []
    var dictationHistory: [DictationEntry] = []
    var showAddModelSheet = false
    var errorMessage: String?

    #if os(iOS)
    var keyboardReady = false
    #elseif os(macOS)
    var accessibilityGranted = false
    #endif

    // MARK: - Private

    private let logger = Logger(subsystem: "com.runanywhere.yaprun", category: "Home")

    // MARK: - Refresh

    func refresh() async {
        // Mic permission
        #if os(iOS)
        let status = AVAudioApplication.shared.recordPermission
        switch status {
        case .granted:    micPermission = .granted
        case .denied:     micPermission = .denied
        default:          micPermission = .unknown
        }
        #elseif os(macOS)
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:            micPermission = .granted
        case .denied, .restricted:   micPermission = .denied
        case .notDetermined:         micPermission = .unknown
        @unknown default:            micPermission = .unknown
        }
        #endif

        // Platform-specific status
        #if os(iOS)
        let hasSessionState = SharedDataBridge.shared.defaults?.string(forKey: SharedConstants.Keys.sessionState) != nil
        keyboardReady = hasSessionState
        #elseif os(macOS)
        accessibilityGranted = AXIsProcessTrusted()
        #endif

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
        #if os(iOS)
        let granted = await AVAudioApplication.requestRecordPermission()
        micPermission = granted ? .granted : .denied
        #elseif os(macOS)
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        micPermission = granted ? .granted : .denied
        #endif
    }

    func openSettings() {
        #if os(iOS)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #elseif os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }

    #if os(macOS)
    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    #endif

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

            #if os(iOS)
            SharedDataBridge.shared.preferredSTTModelId = modelId
            #else
            UserDefaults.standard.set(modelId, forKey: "preferredSTTModelId")
            #endif

            logger.info("Model \(modelId) downloaded and loaded")
        } catch {
            errorMessage = "Download failed: \(error.localizedDescription)"
            logger.error("Download failed for \(modelId): \(error.localizedDescription)")
        }

        downloadingIds.remove(modelId)
        downloadProgress.removeValue(forKey: modelId)
        await refresh()
    }

    func loadModel(_ modelId: String) async {
        do {
            try await RunAnywhere.loadSTTModel(modelId)
            currentSTTModelId = modelId

            #if os(iOS)
            SharedDataBridge.shared.preferredSTTModelId = modelId
            #else
            UserDefaults.standard.set(modelId, forKey: "preferredSTTModelId")
            #endif

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
        #if os(iOS)
        SharedDataBridge.shared.defaults?.removeObject(forKey: SharedConstants.Keys.dictationHistory)
        #else
        DictationHistory.shared.clear()
        #endif
    }

    private func loadHistory() {
        #if os(iOS)
        guard let data = SharedDataBridge.shared.defaults?.data(forKey: SharedConstants.Keys.dictationHistory),
              let entries = try? JSONDecoder().decode([DictationEntry].self, from: data) else {
            dictationHistory = []
            return
        }
        dictationHistory = entries
        #else
        dictationHistory = DictationHistory.shared.entries
        #endif
    }
}

// MARK: - ModelInfo Helpers

extension ModelInfo {
    var sizeLabel: String {
        if let size = downloadSize, size > 0 {
            return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        }
        return "Unknown size"
    }

    var frameworkBadge: String {
        switch framework {
        case .whisperKitCoreML: return "Neural Engine"
        case .onnx:       return "ONNX CPU"
        default:          return framework.rawValue
        }
    }

    var engineNote: String {
        switch framework {
        case .whisperKitCoreML: return "Optimized - runs on Apple Neural Engine with low CPU and memory usage"
        case .onnx:       return "High CPU usage - runs entirely on CPU with higher memory consumption"
        default:          return ""
        }
    }

    var frameworkColor: Color {
        switch framework {
        case .onnx:             return .orange
        case .llamaCpp:         return .purple
        case .foundationModels: return .blue
        case .coreml:           return .cyan
        case .whisperKitCoreML:       return .green
        default:                return .gray
        }
    }
}
