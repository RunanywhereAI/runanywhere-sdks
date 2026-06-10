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
class STTViewModel: VoiceComponentViewModelBase {
    private let audioCapture = AudioCaptureManager()

    // MARK: - Component Identity

    override var component: RASDKComponent { .stt }
    override var eventCategory: RAEventCategory { .stt }
    override var modelCategory: RAModelCategory { .speechRecognition }

    // MARK: - Published Properties (UI State)

    @Published var transcription: String = ""
    @Published var isRecording = false
    @Published var isProcessing = false
    @Published var isTranscribing = false
    @Published var audioLevel: Float = 0.0
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

    /// Batch mode: accumulated audio transcribed once on stop.
    private var audioBuffer = Data()

    /// Live mode: mic chunks are fed straight into the SDK's streaming
    /// transcription session (`RunAnywhere.transcribeStream`), which owns
    /// endpointing/segmentation natively. No app-side silence detection.
    private var liveAudioContinuation: AsyncStream<Data>.Continuation?
    private var liveStreamTask: Task<Void, Never>?
    private var committedTranscription = ""

    // MARK: - Initialization State (for idempotency)

    private var hasSubscribedToAudioLevel = false

    // MARK: - Initialization

    init() {
        super.init(loggerCategory: "STT")
        logger.debug("STTViewModel initialized")
    }

    // MARK: - Public Methods

    /// Initialize the ViewModel - request permissions and setup subscriptions
    /// This method is idempotent - calling it multiple times is safe
    func initialize() async {
        guard beginInitialization() else { return }

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
    func loadModelFromSelection(_ model: RAModelInfo) async {
        isProcessing = true
        await loadModel(from: model)
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

    /// STT resolves the display name from the model catalog when available,
    /// falling back to the id-derived name.
    override func applyLoadedModel(_ model: RAModelInfo) {
        selectedModelId = model.id
        if let matchingModel = ModelListViewModel.shared.availableModels.first(where: { $0.id == model.id }) {
            selectedModelName = matchingModel.name
            selectedFramework = matchingModel.framework
        } else {
            selectedModelName = model.id.modelNameFromID()
            selectedFramework = model.framework
        }
    }

    // MARK: - Private Methods - Recording

    private func startRecording() async {
        logger.info("Starting recording in \(self.selectedMode.rawValue) mode")
        errorMessage = nil
        audioBuffer = Data()
        transcription = ""
        committedTranscription = ""

        guard selectedModelId != nil else {
            errorMessage = "No STT model loaded"
            return
        }

        if selectedMode == .live {
            startLiveTranscription()
        }

        do {
            // Batch buffers locally; live feeds the SDK streaming session.
            try await AudioCapturePump.startRecording(with: audioCapture) { [weak self] audioData in
                guard let self else { return }
                if self.selectedMode == .live {
                    self.liveAudioContinuation?.yield(audioData)
                } else {
                    self.audioBuffer.append(audioData)
                }
            }

            isRecording = true
            logger.info("Recording started in \(self.selectedMode.rawValue) mode")
        } catch {
            logger.error("Failed to start recording: \(error.localizedDescription)")
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
            await stopLiveTranscription()
        }
    }

    private func stopRecording() async {
        logger.info("Stopping recording")

        // Stop audio capture
        audioCapture.stopRecording()

        if selectedMode == .live {
            // Closing the audio stream lets the native session flush and emit
            // its final result; the consume task ends with the stream.
            liveAudioContinuation?.finish()
            liveAudioContinuation = nil
        } else if !audioBuffer.isEmpty {
            // Batch: transcribe everything we recorded.
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
            let output = try await RunAnywhere.transcribe(audio: audioBuffer)
            transcription = output.text
            logger.info("Batch transcription complete: \(output.text)")
        } catch {
            logger.error("Batch transcription failed: \(error.localizedDescription)")
            errorMessage = "Transcription failed: \(error.localizedDescription)"
        }

        isTranscribing = false
    }

    /// Start the SDK streaming transcription session for live mode.
    ///
    /// Mic chunks are yielded into an `AsyncStream<Data>` consumed by
    /// `RunAnywhere.transcribeStream`; the native session owns segmentation
    /// and emits partial + final results.
    private func startLiveTranscription() {
        logger.info("Starting live streaming transcription")

        let (stream, continuation) = AsyncStream<Data>.makeStream()
        liveAudioContinuation = continuation

        liveStreamTask = Task { [weak self] in
            for await partial in RunAnywhere.transcribeStream(audio: stream) {
                guard let self, !Task.isCancelled else { break }
                self.handleLivePartial(partial)
            }
            self?.logger.info("Live transcription stream ended")
        }
    }

    /// Fold one streaming partial into the displayed transcription:
    /// non-final partials preview the current utterance, finals commit it.
    private func handleLivePartial(_ partial: RASTTPartialResult) {
        let text = partial.text.trimmingCharacters(in: .whitespacesAndNewlines)

        if partial.isFinal {
            // Stream errors surface as a terminal partial carrying the
            // failure text (see RunAnywhere.transcribeStream).
            if text.hasPrefix("STT stream failed") {
                errorMessage = text
                return
            }
            if !text.isEmpty {
                committedTranscription = committedTranscription.isEmpty
                    ? text
                    : committedTranscription + "\n" + text
            }
            transcription = committedTranscription
        } else if !text.isEmpty {
            transcription = committedTranscription.isEmpty
                ? text
                : committedTranscription + "\n" + text
        }
    }

    /// Stop live transcription (called when mode changes)
    private func stopLiveTranscription() async {
        logger.info("Stopping live transcription")
        liveAudioContinuation?.finish()
        liveAudioContinuation = nil
        liveStreamTask?.cancel()
        liveStreamTask = nil
    }

    // MARK: - Cleanup

    /// Clean up resources - call from view's onDisappear
    /// This replaces deinit cleanup to comply with Swift 6 concurrency
    func cleanup() {
        audioCapture.stopRecording()

        liveAudioContinuation?.finish()
        liveAudioContinuation = nil
        liveStreamTask?.cancel()
        liveStreamTask = nil

        hasSubscribedToAudioLevel = false
        cleanupBase()
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
        case .live: return "Stream with live partial results"
        }
    }
}
