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

    /// For live mode: VAD-based transcription
    private var lastSpeechTime: Date?
    private var isSpeechActive = false
    private var silenceCheckTask: Task<Void, Never>?
    private let speechThreshold: Float = 0.02  // Audio level threshold for speech detection
    private let silenceDuration: TimeInterval = 1.5  // Seconds of silence before transcribing

    // MARK: - Initialization State (for idempotency)

    private var isInitialized = false
    private var didAutoPrepareSTT = false
    private var hasSubscribedToAudioLevel = false
    private var hasSubscribedToSDKEvents = false

    private static let defaultSTTModelID = "sherpa-onnx-whisper-tiny.en"

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
        await prepareDefaultSTTModelIfNeeded()
    }

    /// Download and load the default Sherpa STT model when the Transcribe tab opens.
    /// Runs before the model picker sheet so simulator harness reaches download/load
    /// os_log markers without brittle Get taps (SWIFT-IOS-001).
    private func prepareDefaultSTTModelIfNeeded() async {
        guard !didAutoPrepareSTT else { return }
        didAutoPrepareSTT = true

        logger.info("STT auto-prepare started (SWIFT-IOS-001)")

        await ModelListViewModel.shared.loadModels()
        let sttModels = ModelListViewModel.shared.availableModels.filter {
            $0.category == .speechRecognition && !$0.isBuiltIn
        }

        let preferred = sttModels.first { $0.id == Self.defaultSTTModelID }
        let readyOnDisk = preferred.flatMap { $0.localPathURL != nil ? $0 : nil }
            ?? sttModels.first { $0.localPathURL != nil }
        let downloadable = preferred.flatMap { $0.localPathURL == nil ? $0 : nil }
            ?? sttModels.first { $0.localPathURL == nil }

        if let readyOnDisk {
            await loadModelFromSelection(readyOnDisk)
            return
        }

        guard let downloadable else {
            logger.error(
                "STT auto-prepare skipped: no downloadable STT model (registry count=\(sttModels.count, privacy: .public))"
            )
            return
        }

        isProcessing = true
        errorMessage = nil
        defer { isProcessing = false }

        do {
            try await RunAnywhere.downloadModel(downloadable) { _ in }
            await ModelListViewModel.shared.loadModels()
            let refreshed = ModelListViewModel.shared.availableModels.first { $0.id == downloadable.id }
                ?? downloadable
            await loadModelFromSelection(refreshed)
        } catch {
            let message = (error as? SDKException)?.message ?? error.localizedDescription
            logger.error("STT auto-prepare download failed: \(message, privacy: .public)")
            errorMessage = message.isEmpty
                ? "Failed to download \(downloadable.name)."
                : "Failed to download \(downloadable.name): \(message)"
        }
    }

    /// Load model from ModelSelectionSheet selection
    func loadModelFromSelection(_ model: RAModelInfo) async {
        logger.info("Loading STT model from selection: \(model.name)")
        isProcessing = true
        errorMessage = nil

        var request = RAModelLoadRequest()
        request.modelID = model.id
        request.category = .speechRecognition
        let result = await RunAnywhere.loadModel(request)
        if result.success {
            selectedFramework = model.framework
            selectedModelName = model.name.modelNameFromID()
            selectedModelId = model.id
            logger.info("STT model loaded successfully: \(model.name)")
            Logger(subsystem: "com.runanywhere", category: "Models").info(
                "Model load succeeded for \(model.id, privacy: .public)"
            )
            Logger(subsystem: "com.runanywhere", category: "STT").info(
                "STT model loaded successfully: \(model.name, privacy: .public)"
            )
        } else {
            logger.error("Failed to load STT model: \(result.errorMessage)")
            errorMessage = "Failed to load model: \(result.errorMessage)"
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

    private func handleSDKEvent(_ event: RASDKEvent) {
        guard event.category == .stt || event.component == .stt else { return }

        let modelId = event.model.modelID

        switch event.model.kind {
        case .loadCompleted:
            selectedModelId = modelId
            // Look up the model name from available models
            if let matchingModel = ModelListViewModel.shared.availableModels.first(where: { $0.id == modelId }) {
                selectedModelName = matchingModel.name
                selectedFramework = matchingModel.framework
            } else {
                selectedModelName = modelId.modelNameFromID() // Look up proper name
            }
            logger.info("STT model loaded: \(modelId)")
        case .unloadCompleted:
            selectedModelId = nil
            selectedModelName = nil
            selectedFramework = nil
            logger.info("STT model unloaded")
        default:
            break
        }
    }

    private func checkInitialModelState() async {
        var req = RACurrentModelRequest()
        req.category = .speechRecognition
        let snapshot = RunAnywhere.currentModel(req)
        if snapshot.found {
            let model = snapshot.model
            selectedModelId = model.id
            selectedModelName = model.name.modelNameFromID()
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
        lastSpeechTime = nil
        isSpeechActive = false

        guard selectedModelId != nil else {
            errorMessage = "No STT model loaded"
            return
        }

        do {
            // Both modes use audio capture - live mode adds VAD-based auto-transcription
            try await audioCapture.startRecording { [weak self] audioData in
                Task { @MainActor in
                    self?.audioBuffer.append(audioData)
                }
            }

            isRecording = true

            if selectedMode == .live {
                // Live mode: Start VAD monitoring for auto-transcription
                startVADMonitoring()
            }

            logger.info("Recording started in \(self.selectedMode.rawValue) mode")
        } catch {
            logger.error("Failed to start recording: \(error.localizedDescription)")
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
        }
    }

    private func stopRecording() async {
        logger.info("Stopping recording")

        // Stop VAD monitoring if active
        silenceCheckTask?.cancel()
        silenceCheckTask = nil

        // Stop audio capture
        audioCapture.stopRecording()

        // Perform final transcription if we have audio
        if !audioBuffer.isEmpty {
            await performBatchTranscription()
        }

        isRecording = false
        audioLevel = 0.0
        isSpeechActive = false
        lastSpeechTime = nil
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
            let output = try await RunAnywhere.transcribe(audio: audioBuffer)
            transcription = output.text
            logger.info("Batch transcription complete: \(output.text)")
        } catch {
            logger.error("Batch transcription failed: \(error.localizedDescription)")
            errorMessage = "Transcription failed: \(error.localizedDescription)"
        }

        isTranscribing = false
    }

    /// Start VAD monitoring for live mode
    /// Automatically transcribes when silence is detected after speech
    private func startVADMonitoring() {
        logger.info("Starting VAD monitoring for live transcription")

        silenceCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self, self.isRecording else { break }

                let level = self.audioLevel
                await self.checkSpeechState(level: level)

                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            }
        }
    }

    /// Check speech state and auto-transcribe on silence
    private func checkSpeechState(level: Float) async {
        guard isRecording, selectedMode == .live else { return }

        if level > speechThreshold {
            // Speech detected
            if !isSpeechActive {
                logger.debug("Speech started")
                isSpeechActive = true
            }
            lastSpeechTime = Date()
        } else if isSpeechActive {
            // Check for silence duration
            if let lastSpeech = lastSpeechTime,
               Date().timeIntervalSince(lastSpeech) > silenceDuration {
                logger.debug("Silence detected - auto-transcribing")
                isSpeechActive = false

                // Only transcribe if we have enough audio (~0.5s at 16kHz)
                if audioBuffer.count > 16000 {
                    await performLiveTranscription()
                } else {
                    audioBuffer = Data()
                }
            }
        }
    }

    /// Perform transcription for live mode (keeps recording going)
    private func performLiveTranscription() async {
        let audio = audioBuffer
        audioBuffer = Data()  // Clear buffer for next utterance

        guard !audio.isEmpty else { return }

        logger.info("Live transcription of \(audio.count) bytes")
        isTranscribing = true

        do {
            let output = try await RunAnywhere.transcribe(audio: audio)
            // Append to existing transcription with newline
            if !transcription.isEmpty {
                transcription += "\n"
            }
            transcription += output.text
            logger.info("Live transcription result: \(output.text)")
        } catch {
            logger.error("Live transcription failed: \(error.localizedDescription)")
            errorMessage = "Transcription failed: \(error.localizedDescription)"
        }

        isTranscribing = false
    }

    /// Stop live transcription (called when mode changes)
    private func stopLiveTranscription() async {
        logger.info("Stopping live transcription")
        silenceCheckTask?.cancel()
        silenceCheckTask = nil
        isSpeechActive = false
        lastSpeechTime = nil
    }

    // MARK: - Cleanup

    /// Clean up resources - call from view's onDisappear
    /// This replaces deinit cleanup to comply with Swift 6 concurrency
    func cleanup() {
        audioCapture.stopRecording()

        // Clean up VAD monitoring
        silenceCheckTask?.cancel()
        silenceCheckTask = nil

        cancellables.removeAll()

        // Reset initialization flags to allow re-initialization if needed
        isInitialized = false
        didAutoPrepareSTT = false
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
        case .live: return "Auto-transcribe on silence"
        }
    }
}
