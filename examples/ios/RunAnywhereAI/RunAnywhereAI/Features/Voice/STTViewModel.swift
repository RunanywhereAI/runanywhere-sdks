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
                        self.logger.info("Mode changed from \(oldValue.rawValue) to \(self.selectedMode.rawValue) - stopping active recording")
                        await self.stopRecording()
                    }
                    // Also clean up any lingering live transcription resources
                    if oldValue == .live {
                        self.stopLiveTranscription()
                    }
                }
            }
        }
    }

    // MARK: - Private Properties

    private var audioBuffer = Data()
    private var streamingTask: Task<Void, Never>?
    private var audioContinuation: AsyncStream<Data>.Continuation?

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
        if let sttEvent = event as? STTEvent {
            switch sttEvent {
            case .modelLoadCompleted(let modelId, _, _, _):
                selectedModelId = modelId
                // Look up the model name from available models
                if let matchingModel = ModelListViewModel.shared.availableModels.first(where: { $0.id == modelId }) {
                    selectedModelName = matchingModel.name
                    selectedFramework = matchingModel.preferredFramework
                } else {
                    selectedModelName = modelId // Fallback to ID if model not found
                }
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
            if selectedMode == .live {
                // Live mode: Start streaming transcription
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

        // Stop audio capture
        audioCapture.stopRecording()
        isRecording = false
        audioLevel = 0.0

        if selectedMode == .live {
            // Live mode: Stop streaming
            stopLiveTranscription()
        } else {
            // Batch mode: Perform transcription
            await performBatchTranscription()
        }
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

    /// Start live streaming transcription
    private func startLiveTranscription() async throws {
        logger.info("Starting live transcription")
        isTranscribing = true

        // Create audio stream
        let audioStream = AsyncStream<Data> { continuation in
            self.audioContinuation = continuation
        }

        // Start audio capture with stream callback
        try audioCapture.startRecording { [weak self] audioData in
            Task { @MainActor in
                guard let self = self else { return }
                // Send audio chunk to stream
                self.audioContinuation?.yield(audioData)
                // Also buffer for fallback
                self.audioBuffer.append(audioData)
            }
        }

        // Start streaming transcription task
        streamingTask = Task { @MainActor in
            do {
                let transcriptionStream = try await RunAnywhere.transcribeStream(audioStream)

                for try await partialText in transcriptionStream {
                    // Update UI with partial transcription
                    self.transcription = partialText
                    self.logger.debug("Live transcription update: \(partialText)")
                }

                self.logger.info("Live transcription stream completed")
            } catch {
                self.logger.error("Live transcription failed: \(error.localizedDescription)")
                self.errorMessage = "Live transcription failed: \(error.localizedDescription)"
            }

            self.isTranscribing = false
        }
    }

    /// Stop live streaming transcription
    private func stopLiveTranscription() {
        logger.info("Stopping live transcription")

        // Cancel streaming task first to stop consuming from stream
        streamingTask?.cancel()
        streamingTask = nil

        // Finish audio stream (this will cause the transcription stream to complete)
        audioContinuation?.finish()
        audioContinuation = nil

        isTranscribing = false
    }

    // MARK: - Cleanup

    /// Clean up resources - call from view's onDisappear
    /// This replaces deinit cleanup to comply with Swift 6 concurrency
    func cleanup() {
        audioCapture.stopRecording()

        // Clean up streaming resources
        stopLiveTranscription()

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
