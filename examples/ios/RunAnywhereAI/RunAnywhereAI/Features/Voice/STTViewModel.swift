//
//  STTViewModel.swift
//  RunAnywhereAI
//
//  ViewModel for Speech-to-Text functionality
//  Handles all business logic for STT including recording, transcription, and model management
//

import Foundation
import RunAnywhere
import Combine
import os

/// ViewModel for Speech-to-Text view
/// Manages recording, transcription, model selection, and microphone permissions
@MainActor
class STTViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.runanywhere", category: "STT")
    private let audioCapture = AudioCaptureManager()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Published Properties (UI State)

    @Published var selectedFramework: InferenceFramework?
    @Published var selectedModelName: String?
    @Published var selectedModelId: String?
    @Published var transcription: String = ""
    @Published var isRecording = false
    @Published var isProcessing = false
    @Published var isTranscribing = false
    @Published var audioLevel: Float = 0.0
    @Published var errorMessage: String?
    @Published var selectedMode: STTMode = .batch

    // MARK: - Private Properties

    private var audioBuffer = Data()

    // MARK: - Initialization

    init() {
        logger.debug("STTViewModel initialized")
    }

    // MARK: - Public Methods

    /// Initialize the ViewModel - request permissions and setup subscriptions
    func initialize() async {
        logger.info("Initializing STT view model")

        // Request microphone permission
        let hasPermission = await requestMicrophonePermission()
        if !hasPermission {
            errorMessage = "Microphone permission denied"
            logger.error("Microphone permission denied")
            return
        }

        // Subscribe to audio level updates
        subscribeToAudioLevelUpdates()

        // Subscribe to SDK events for STT model state
        subscribeToSDKEvents()

        // Check initial STT model state
        await checkInitialModelState()
    }

    /// Load model from ModelSelectionSheet selection
    func loadModelFromSelection(_ model: ModelInfo) async {
        logger.info("Loading STT model from selection: \(model.name)")
        isProcessing = true
        errorMessage = nil

        do {
            try await RunAnywhere.loadSTTModel(model.id)
            selectedFramework = model.preferredFramework
            selectedModelName = model.name
            selectedModelId = model.id
            logger.info("STT model loaded successfully: \(model.name)")
        } catch {
            logger.error("Failed to load STT model: \(error.localizedDescription)")
            errorMessage = "Failed to load model: \(error.localizedDescription)"
        }

        isProcessing = false
    }

    /// Toggle recording state (start/stop)
    func toggleRecording() async {
        if isRecording {
            await stopRecording()
        } else {
            await startRecording()
        }
    }

    // MARK: - Private Methods - Permissions

    private func requestMicrophonePermission() async -> Bool {
        return await audioCapture.requestPermission()
    }

    // MARK: - Private Methods - Subscriptions

    private func subscribeToAudioLevelUpdates() {
        audioCapture.$audioLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                // Defer state modifications to avoid "Publishing changes within view updates" warning
                Task { @MainActor in
                    self?.audioLevel = level
                }
            }
            .store(in: &cancellables)
    }

    private func subscribeToSDKEvents() {
        RunAnywhere.events.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                // Defer state modifications to avoid "Publishing changes within view updates" warning
                Task { @MainActor in
                    self?.handleSDKEvent(event)
                }
            }
            .store(in: &cancellables)
    }

    private func handleSDKEvent(_ event: any SDKEvent) {
        if let sttEvent = event as? STTEvent {
            switch sttEvent {
            case .modelLoadCompleted(let modelId, _, _):
                selectedModelId = modelId
                selectedModelName = modelId
                logger.info("STT model loaded: \(modelId)")
            case .modelUnloaded:
                selectedModelId = nil
                selectedModelName = nil
                selectedFramework = nil
                logger.info("STT model unloaded")
            default:
                break
            }
        }
    }

    private func checkInitialModelState() async {
        if let model = await RunAnywhere.currentSTTModel {
            selectedModelId = model.id
            selectedModelName = model.name
            selectedFramework = model.preferredFramework
            logger.info("STT model already loaded: \(model.name)")
        }
    }

    // MARK: - Private Methods - Recording

    private func startRecording() async {
        logger.info("Starting recording in \(self.selectedMode.rawValue) mode")
        errorMessage = nil
        audioBuffer = Data()
        transcription = ""

        guard selectedModelId != nil else {
            errorMessage = "No STT model loaded"
            return
        }

        do {
            try audioCapture.startRecording { [weak self] audioData in
                Task { @MainActor in
                    self?.audioBuffer.append(audioData)
                }
            }
            isRecording = true
            logger.info("Recording started")
        } catch {
            logger.error("Failed to start recording: \(error.localizedDescription)")
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
        }
    }

    private func stopRecording() async {
        logger.info("Stopping recording")

        // Stop audio capture
        audioCapture.stopRecording()
        isRecording = false
        audioLevel = 0.0

        // Perform batch transcription
        await performBatchTranscription()
    }

    // MARK: - Private Methods - Transcription

    /// Perform batch transcription on collected audio
    private func performBatchTranscription() async {
        guard !audioBuffer.isEmpty else {
            errorMessage = "No audio recorded"
            return
        }

        logger.info("Starting batch transcription of \(self.audioBuffer.count) bytes")
        isTranscribing = true
        transcription = ""

        do {
            let result = try await RunAnywhere.transcribe(audioBuffer)
            transcription = result
            logger.info("Batch transcription complete: \(result)")
        } catch {
            logger.error("Batch transcription failed: \(error.localizedDescription)")
            errorMessage = "Transcription failed: \(error.localizedDescription)"
        }

        isTranscribing = false
    }

    // MARK: - Cleanup

    deinit {
        audioCapture.stopRecording()
        cancellables.removeAll()
    }
}

// MARK: - Supporting Types

/// STT Mode for UI selection
enum STTMode: String {
    case batch
    case live

    var icon: String {
        switch self {
        case .batch: return "square.stack.3d.up"
        case .live: return "waveform"
        }
    }

    var description: String {
        switch self {
        case .batch: return "Record first, then transcribe"
        case .live: return "Real-time transcription"
        }
    }
}
