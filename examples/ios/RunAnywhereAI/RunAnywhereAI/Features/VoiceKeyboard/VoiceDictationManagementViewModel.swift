//
//  VoiceDictationManagementViewModel.swift
//  RunAnywhereAI
//
//  ViewModel for the Voice Keyboard management screen.
//  Handles model loading, permission checks, and history.
//

#if os(iOS)
import Foundation
import RunAnywhere
import AVFoundation
import os

@MainActor
final class VoiceDictationManagementViewModel: ObservableObject {

    private let logger = Logger(subsystem: "com.runanywhere", category: "VoiceKeyboard.Management")

    // MARK: - Published State

    @Published var microphonePermission: MicrophonePermission = .unknown
    @Published var isKeyboardEnabled: Bool = false
    @Published var loadedModelName: String?
    @Published var loadedModelId: String?
    @Published var isLoadingModel = false
    @Published var errorMessage: String?
    @Published var dictationHistory: [DictationEntry] = []
    @Published var showModelPicker = false

    // MARK: - Init

    init() {}

    // MARK: - Lifecycle

    func onAppear() async {
        await refreshAll()
    }

    func onForeground() async {
        await refreshAll()
    }

    // MARK: - Refresh

    private func refreshAll() async {
        await checkMicrophonePermission()
        checkKeyboardEnabled()
        await checkLoadedModel()
        loadHistory()
    }

    // MARK: - Microphone

    func requestMicrophonePermission() async {
        let granted = await AVAudioApplication.requestRecordPermission()
        microphonePermission = granted ? .granted : .denied
    }

    private func checkMicrophonePermission() async {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:   microphonePermission = .granted
        case .denied:    microphonePermission = .denied
        case .undetermined: microphonePermission = .unknown
        @unknown default: microphonePermission = .unknown
        }
    }

    // MARK: - Keyboard Enabled

    private func checkKeyboardEnabled() {
        // Detect whether the user has added RunAnywhereKeyboard in iOS Settings.
        // The reliable signal is that App Group UserDefaults are accessible — a proxy indicator.
        // True detection requires iterating UITextInputMode, which is not possible outside a text field.
        isKeyboardEnabled = SharedDataBridge.shared.defaults != nil
    }

    // MARK: - Model

    private func checkLoadedModel() async {
        if let model = await RunAnywhere.currentSTTModel {
            loadedModelId = model.id
            loadedModelName = model.name
        } else {
            loadedModelId = nil
            loadedModelName = nil
        }
    }

    func loadModel(_ model: ModelInfo) async {
        logger.info("Loading STT model: \(model.name)")
        isLoadingModel = true
        errorMessage = nil
        do {
            try await RunAnywhere.loadSTTModel(model.id)
            loadedModelId = model.id
            loadedModelName = model.name
            SharedDataBridge.shared.preferredSTTModelId = model.id
            logger.info("STT model loaded: \(model.name)")
        } catch {
            errorMessage = "Failed to load model: \(error.localizedDescription)"
            logger.error("Model load failed: \(error.localizedDescription)")
        }
        isLoadingModel = false
    }

    // MARK: - History

    private func loadHistory() {
        guard let defaults = SharedDataBridge.shared.defaults,
              let data = defaults.data(forKey: SharedConstants.Keys.dictationHistory),
              let entries = try? JSONDecoder().decode([DictationEntry].self, from: data)
        else {
            dictationHistory = []
            return
        }
        dictationHistory = entries
    }

    func clearHistory() {
        SharedDataBridge.shared.defaults?.removeObject(forKey: SharedConstants.Keys.dictationHistory)
        dictationHistory = []
    }
}

// MARK: - Supporting Types

enum MicrophonePermission {
    case unknown, granted, denied

    var label: String {
        switch self {
        case .unknown: return "Not determined"
        case .granted: return "Granted"
        case .denied:  return "Denied"
        }
    }

    var systemImage: String {
        switch self {
        case .unknown: return "questionmark.circle"
        case .granted: return "checkmark.circle.fill"
        case .denied:  return "xmark.circle.fill"
        }
    }
}

#endif
