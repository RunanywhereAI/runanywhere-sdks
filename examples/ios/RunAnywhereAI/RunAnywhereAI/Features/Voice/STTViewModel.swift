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
    /// `AudioCaptureManager` delivers mono Int16 PCM at this rate.
    private static let captureSampleRate = 16_000

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
    @Published var cloudProviderId = "runanywhere-cloud-stt"
    @Published var cloudProvider = Cloud.defaultProvider
    @Published var cloudModel = "saarika:v2.5"
    @Published var cloudAPIKey = ""
    @Published var cloudLanguageCode = "en-IN"
    @Published var hybridPreferOnline = false
    @Published var hybridRequireNetwork = true
    @Published var hybridMinBattery: Double = 20
    @Published var hybridConfidenceThreshold = Double(RAHybridSTTConfidenceThreshold)
    @Published var hybridRouting: HybridRoutedMetadata?
    /// A recording finished and the engine recognised nothing in it.
    ///
    /// Distinct from "nothing recorded yet": commons now publishes an engine's
    /// own no-speech marker as empty text, so an honestly silent recording is
    /// an empty transcript, and the screen has to say which of the two it is.
    @Published private(set) var noSpeechDetected = false
    @Published var selectedMode: STTMode = .batch {
        didSet {
            // Stop any active recording/transcription when mode changes
            if oldValue != selectedMode {
                // Drop the previous mode's result immediately. Leaving it under
                // the new mode's description attributes one mode's output to
                // another — a Batch "[ Silence ]" read as a Live result. Same
                // reset `startRecording` already performs. Synchronous, so the
                // stale text cannot survive even one frame.
                transcription = ""
                committedTranscription = ""
                hybridRouting = nil
                errorMessage = nil
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
    /// transcription session (`RunAnywhere.stt.transcribeStream`), which owns
    /// endpointing/segmentation natively. No app-side silence detection.
    private var liveAudioContinuation: AsyncStream<AudioInput>.Continuation?
    private var liveStreamTask: Task<Void, Never>?
    private var committedTranscription = ""
    private var hybridRouter: HybridSTTRouter?
    private var hybridPairKey: String?

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
        hybridRouting = nil
        audioBuffer = Data()
        transcription = ""
        committedTranscription = ""
        noSpeechDetected = false

        guard selectedModelId != nil else {
            errorMessage = "No STT model loaded"
            return
        }

        if selectedMode == .hybrid && !isHybridCloudConfigValid {
            errorMessage = "Enter a cloud STT API key before using Hybrid mode"
            return
        }

        if selectedMode == .live {
            guard await startLiveTranscription() else { return }
        }

        do {
            // Batch buffers locally; live feeds the SDK streaming session.
            try await AudioCapturePump.startRecording(with: audioCapture) { [weak self] audioData in
                guard let self else { return }
                if self.selectedMode == .live {
                    self.liveAudioContinuation?.yield(.pcm16(audioData, sampleRate: Self.captureSampleRate))
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
            if selectedMode == .hybrid {
                await performHybridTranscription()
            } else {
                // Batch: transcribe everything we recorded.
                await performBatchTranscription()
            }
        }

        isRecording = false
        audioLevel = 0.0
        // "Recorded, and nothing was recognised" is a different fact from
        // "nothing recorded yet", and the screen used to show the second for
        // both — telling the user they never recorded when in fact seconds of
        // audio were captured and came back empty. Live mode settles
        // asynchronously, so it raises the flag from its own completion.
        if selectedMode != .live {
            noSpeechDetected = !audioBuffer.isEmpty && transcription.isEmpty && errorMessage == nil
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
            let result = try await RunAnywhere.stt.transcribe(
                .pcm16(audioBuffer, sampleRate: Self.captureSampleRate)
            )
            transcription = result.text
            logger.info("Batch transcription complete: \(result.text)")
        } catch {
            logger.error("Batch transcription failed: \(error.localizedDescription)")
            errorMessage = "Transcription failed: \(error.localizedDescription)"
        }

        isTranscribing = false
    }

    /// Perform one request through the SDK hybrid STT router.
    private func performHybridTranscription() async {
        guard !audioBuffer.isEmpty else {
            errorMessage = "No audio recorded"
            return
        }
        guard let offlineModelId = selectedModelId else {
            errorMessage = "No STT model loaded"
            return
        }

        logger.info("Starting hybrid transcription of \(self.audioBuffer.count) bytes")
        isTranscribing = true
        transcription = ""
        hybridRouting = nil

        do {
            let onlineModelId = try registerCloudProvider()
            let router = try ensureHybridRouter(offlineModelId: offlineModelId, onlineModelId: onlineModelId)
            var options = HybridTranscribeOptions()
            options.sampleRate = 16_000
            // `HybridSttTranscribeOptions.audio_format` was retyped from a raw
            // int32 to the shared `AudioFormat` enum (idl/hybrid_router.proto:
            // "Untyped: every other file uses the AudioFormat enum here.").
            options.audioFormat = .wav

            let result = try router.transcribe(audioBuffer, options: options)
            transcription = result.text
            hybridRouting = result.routing
            logger.info("Hybrid transcription complete: \(result.text)")
        } catch {
            logger.error("Hybrid transcription failed: \(error.localizedDescription)")
            errorMessage = "Hybrid transcription failed: \(error.localizedDescription)"
        }

        isTranscribing = false
    }

    private var isHybridCloudConfigValid: Bool {
        !cloudProviderId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !cloudProvider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !cloudModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !cloudAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func registerCloudProvider() throws -> String {
        let id = cloudProviderId.trimmingCharacters(in: .whitespacesAndNewlines)
        let provider = cloudProvider.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = cloudModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = cloudAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let language = cloudLanguageCode.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !id.isEmpty, !provider.isEmpty, !model.isEmpty, !apiKey.isEmpty else {
            throw SDKException(
                code: .invalidArgument,
                message: "Cloud provider id, provider, model, and API key are required",
                category: .validation
            )
        }

        Cloud.register()
        Cloud.register(
            id: id,
            provider: provider,
            model: model,
            apiKey: apiKey,
            languageCode: language.isEmpty ? nil : language
        )
        return id
    }

    private func ensureHybridRouter(offlineModelId: String, onlineModelId: String) throws -> HybridSTTRouter {
        let key = [
            offlineModelId,
            onlineModelId,
            cloudProvider,
            String(hybridPreferOnline),
            String(hybridRequireNetwork),
            String(Int(hybridMinBattery)),
            String(hybridConfidenceThreshold),
        ].joined(separator: "|")

        if let router = hybridRouter, hybridPairKey == key {
            return router
        }

        hybridRouter?.close()
        let router = try HybridSTTRouter()
        var filters: [HybridFilter] = []
        if hybridRequireNetwork { filters.append(.network) }
        filters.append(.battery(minPercent: Int32(hybridMinBattery)))
        // `HybridModel.onlineCloud(_:)` no longer takes `provider:`
        // (idl/hybrid_router.proto deleted `HybridModelDescriptor.provider`
        // outright) -- the concrete provider is resolved by the cloud engine
        // from the config registered via `Cloud.register(id:provider:...)`
        // in `registerCloudProvider()` above, keyed by `onlineModelId`.
        try router.setPair(
            offline: .offlineSherpa(offlineModelId),
            online: .onlineCloud(onlineModelId),
            policy: HybridRoutingPolicy(
                hardFilters: filters,
                cascade: .confidence(threshold: Float(hybridConfidenceThreshold)),
                preferLocal: !hybridPreferOnline
            )
        )
        hybridRouter = router
        hybridPairKey = key
        return router
    }

    /// Start the SDK streaming transcription session for live mode.
    ///
    /// Mic chunks are yielded into an `AsyncStream<AudioInput>` consumed by
    /// `RunAnywhere.stt.transcribeStream`; the native session owns segmentation
    /// and emits partial + final results.
    ///
    /// - Returns: `false` when the session could not be opened, in which case
    ///   the caller must not start audio capture.
    private func startLiveTranscription() async -> Bool {
        logger.info("Starting live streaming transcription")

        let (stream, continuation) = AsyncStream<AudioInput>.makeStream()

        let events: AsyncThrowingStream<TranscriptionEvent, Error>
        do {
            events = try await RunAnywhere.stt.transcribeStream(stream)
        } catch {
            continuation.finish()
            logger.error("Live transcription failed to start: \(error.localizedDescription)")
            errorMessage = "Live transcription failed to start: \(error.localizedDescription)"
            return false
        }

        liveAudioContinuation = continuation
        liveStreamTask = Task { [weak self] in
            do {
                for try await event in events {
                    guard let self, !Task.isCancelled else { break }
                    self.handleTranscriptionEvent(event)
                }
                self?.logger.info("Live transcription stream ended")
                // The live session settles after `stopRecording` has returned,
                // so it raises the no-speech flag itself rather than leaving the
                // screen on "nothing recorded yet" after a real recording.
                if let self, !Task.isCancelled, self.errorMessage == nil {
                    self.noSpeechDetected = self.transcription.isEmpty
                }
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.logger.error("Live transcription failed: \(error.localizedDescription)")
                self.errorMessage = "Live transcription failed: \(error.localizedDescription)"
            }
        }
        return true
    }

    /// Fold one streaming event into the displayed transcription:
    /// partials preview the current utterance, finals commit it.
    private func handleTranscriptionEvent(_ event: TranscriptionEvent) {
        switch event {
        case .started:
            break

        case .partial(_, _, _, _, let alternatives):
            let preview = (alternatives.first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !preview.isEmpty else { return }
            transcription = committedTranscription.isEmpty
                ? preview
                : committedTranscription + "\n" + preview

        case .transcriptFinal(_, _, let result):
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                committedTranscription = committedTranscription.isEmpty
                    ? text
                    : committedTranscription + "\n" + text
            }
            transcription = committedTranscription

        default:
            break
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
        hybridRouter?.close()
        hybridRouter = nil
        hybridPairKey = nil

        hasSubscribedToAudioLevel = false
        cleanupBase()
    }
}

// MARK: - Supporting Types

/// STT Mode for UI selection
enum STTMode: String {
    case batch
    case live
    case hybrid

    var icon: String {
        switch self {
        case .batch: return "square.stack.3d.up"
        case .live: return "waveform"
        case .hybrid: return "cloud"
        }
    }

    var description: String {
        switch self {
        case .batch: return "Record first, then transcribe"
        case .live: return "Stream with live partial results"
        case .hybrid: return "On-device first with cloud fallback"
        }
    }
}
