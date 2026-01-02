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
    @Published var selectedMode: STTMode = .batch {
        didSet {
            // Stop any active recording/transcription when mode changes
            if oldValue != selectedMode {
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    if self.isRecording {
                        let msg = "Mode changed from \(oldValue.rawValue) to \(self.selectedMode.rawValue)"
                        self.logger.info("\(msg) - stopping active recording")
                        await self.stopRecording()
                    }
                    // Also clean up any lingering live transcription resources
                    if oldValue == .live {
                        await self.stopLiveTranscription()
                    }
                }
            }
        }
    }

    // MARK: - Private Properties

    private var audioBuffer = Data()

    /// SDK-managed live transcription session (handles audio capture + streaming internally)
    private var liveSession: LiveTranscriptionSession?

    // MARK: - Initialization State (for idempotency)

    private var isInitialized = false
    private var hasSubscribedToAudioLevel = false
    private var hasSubscribedToSDKEvents = false

    // MARK: - Initialization

    init() {
        logger.debug("STTViewModel initialized")
    }

    // MARK: - Public Methods

    /// Initialize the ViewModel - request permissions and setup subscriptions
    /// This method is idempotent - calling it multiple times is safe
    func initialize() async {
        guard !isInitialized else {
            logger.debug("STT view model already initialized, skipping")
            return
        }
        isInitialized = true

        logger.info("Initializing STT view model")

        // Request microphone permission
        let hasPermission = await requestMicrophonePermission()
        if !hasPermission {
            errorMessage = "Microphone permission denied"
            logger.error("Microphone permission denied")
            return
        }

        // Subscribe to audio level updates (for batch mode)
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
            selectedFramework = model.framework
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
        await audioCapture.requestPermission()
    }

    // MARK: - Private Methods - Subscriptions

    private func subscribeToAudioLevelUpdates() {
        guard !hasSubscribedToAudioLevel else {
            logger.debug("Already subscribed to audio level updates, skipping")
            return
        }
        hasSubscribedToAudioLevel = true

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
        guard !hasSubscribedToSDKEvents else {
            logger.debug("Already subscribed to SDK events, skipping")
            return
        }
        hasSubscribedToSDKEvents = true

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
        // Events now come from C++ via generic BridgedEvent
        guard event.category == .stt else { return }

        switch event.type {
        case "stt_model_load_completed":
            let modelId = event.properties["model_id"] ?? ""
            selectedModelId = modelId
            // Look up the model name from available models
            if let matchingModel = ModelListViewModel.shared.availableModels.first(where: { $0.id == modelId }) {
                selectedModelName = matchingModel.name
                selectedFramework = matchingModel.framework
            } else {
                selectedModelName = modelId // Fallback to ID if model not found
            }
            logger.info("STT model loaded: \(modelId)")
        case "stt_model_unloaded":
            selectedModelId = nil
            selectedModelName = nil
            selectedFramework = nil
            logger.info("STT model unloaded")
        default:
            break
        }
    }

    private func checkInitialModelState() async {
        if let model = await RunAnywhere.currentSTTModel {
            selectedModelId = model.id
            selectedModelName = model.name
            selectedFramework = model.framework
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
            if selectedMode == .live {
                // Live mode: Use SDK's LiveTranscriptionSession (handles audio capture internally)
                try await startLiveTranscription()
            } else {
                // Batch mode: Collect audio for later transcription
                try audioCapture.startRecording { [weak self] audioData in
                    Task { @MainActor in
                        self?.audioBuffer.append(audioData)
                    }
                }
            }
            isRecording = true
            logger.info("Recording started in \(self.selectedMode.rawValue) mode")
        } catch {
            logger.error("Failed to start recording: \(error.localizedDescription)")
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
        }
    }

    private func stopRecording() async {
        logger.info("Stopping recording")

        if selectedMode == .live {
            // Live mode: Stop SDK session (handles audio cleanup internally)
            await stopLiveTranscription()
        } else {
            // Batch mode: Stop audio capture and perform transcription
            audioCapture.stopRecording()
            await performBatchTranscription()
        }

        isRecording = false
        audioLevel = 0.0
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

    /// Start live streaming transcription using SDK's LiveTranscriptionSession
    private func startLiveTranscription() async throws {
        logger.info("Starting live transcription via SDK")

        // Start session
        let session = try await RunAnywhere.startLiveTranscription()
        self.liveSession = session

        // Bind directly to SDK's published properties instead of manually iterating streams
        // This eliminates state duplication and uses the SDK's reactive bindings

        // Bind audio level directly from session
        session.$audioLevel
            .receive(on: DispatchQueue.main)
            .assign(to: &$audioLevel)

        // Bind transcription text directly from session's published property
        session.$currentText
            .receive(on: DispatchQueue.main)
            .assign(to: &$transcription)

        // Bind isActive to isTranscribing (session manages this state)
        session.$isActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isActive in
                self?.isTranscribing = isActive
                if !isActive {
                    self?.logger.info("Live transcription completed")
                }
            }
            .store(in: &cancellables)

        // Bind error from session to propagate transcription errors
        session.$error
            .receive(on: DispatchQueue.main)
            .compactMap { $0?.localizedDescription }
            .sink { [weak self] errorDescription in
                self?.errorMessage = "Transcription error: \(errorDescription)"
            }
            .store(in: &cancellables)
    }

    /// Stop live streaming transcription
    private func stopLiveTranscription() async {
        logger.info("Stopping live transcription")

        await liveSession?.stop()
        liveSession = nil

        // Note: isTranscribing is automatically set to false via session.$isActive binding
    }

    // MARK: - Cleanup

    /// Clean up resources - call from view's onDisappear
    /// This replaces deinit cleanup to comply with Swift 6 concurrency
    func cleanup() {
        audioCapture.stopRecording()

        // Clean up live transcription session
        Task { @MainActor in
            await liveSession?.stop()
            liveSession = nil
        }

        cancellables.removeAll()

        // Reset initialization flags to allow re-initialization if needed
        isInitialized = false
        hasSubscribedToAudioLevel = false
        hasSubscribedToSDKEvents = false
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
