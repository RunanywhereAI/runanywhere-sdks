import Foundation
import RunAnywhere
import Combine
import os

/// ViewModel for Voice Activity Detection functionality
/// Manages microphone capture, VAD model loading, and real-time speech detection
@MainActor
class VADViewModel: VoiceComponentViewModelBase {
    /// `AudioCaptureManager` delivers mono Int16 PCM at this rate.
    private static let captureSampleRate = 16_000

    private let audioCapture = AudioCaptureManager()

    // MARK: - Component Identity

    override var component: RASDKComponent { .vad }
    override var eventCategory: RAEventCategory { .vad }
    override var modelCategory: RAModelCategory { .voiceActivityDetection }

    // MARK: - Published Properties (UI State)

    @Published var isListening = false
    @Published var isProcessing = false
    @Published var isSpeechDetected = false
    @Published var audioLevel: Float = 0.0

    /// Log of speech activity events with timestamps
    @Published var activityLog: [SpeechActivityLogEntry] = []

    // MARK: - Private Properties

    /// Mic chunks are fed straight into the SDK's `vad.detectStream` session;
    /// the SDK owns model framing — no app-side buffer math.
    private var vadAudioContinuation: AsyncStream<AudioInput>.Continuation?
    private var detectionTask: Task<Void, Never>?
    private var hasSubscribedToAudioLevel = false

    // MARK: - Initialization

    init() {
        super.init(loggerCategory: "VAD")
        logger.debug("VADViewModel initialized")
    }

    /// Initialize the ViewModel - request permissions and setup subscriptions
    func initialize() async {
        guard beginInitialization() else { return }

        logger.info("Initializing VAD view model")

        // Request microphone permission
        let hasPermission = await requestMicrophonePermission()
        if !hasPermission {
            errorMessage = "Microphone permission denied"
            logger.error("Microphone permission denied")
            return
        }

        // Subscribe to audio level updates
        subscribeToAudioLevelUpdates()

        // Subscribe to SDK events for VAD model state
        subscribeToSDKEvents()

        // Check initial VAD model state
        await checkInitialModelState()
    }

    // MARK: - Model Management

    /// Load model from ModelSelectionSheet selection
    func loadModelFromSelection(_ model: RAModelInfo) async {
        isProcessing = true
        await loadModel(from: model)
        isProcessing = false
    }

    // MARK: - Listening Control

    /// Toggle listening state (start/stop)
    func toggleListening() async {
        if isListening {
            await stopListening()
        } else {
            await startListening()
        }
    }

    /// Clear the activity log
    func clearLog() {
        activityLog.removeAll()
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
                Task { @MainActor in
                    self?.audioLevel = level
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - SDK Event Handling

    /// VAD resolves the display name from the model catalog when available,
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

    // MARK: - Private Methods - Listening

    private func startListening() async {
        logger.info("Starting VAD listening")
        errorMessage = nil
        isSpeechDetected = false

        guard selectedModelId != nil else {
            errorMessage = "No VAD model loaded"
            return
        }

        guard await startDetectionStream() else { return }

        do {
            try await AudioCapturePump.startRecording(with: audioCapture) { [weak self] audioData in
                guard let self else { return }
                // Encoding and framing are handled natively.
                self.vadAudioContinuation?.yield(.pcm16(audioData, sampleRate: Self.captureSampleRate))
            }

            isListening = true
            logger.info("VAD listening started")
        } catch {
            logger.error("Failed to start recording: \(error.localizedDescription)")
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
            stopDetectionStream()
        }
    }

    private func stopListening() async {
        logger.info("Stopping VAD listening")

        audioCapture.stopRecording()
        stopDetectionStream()

        isListening = false
        isSpeechDetected = false
        audioLevel = 0.0
    }

    /// Consume the SDK's streaming VAD session. The SDK emits the
    /// speech-start/end transitions that drive the activity list, plus a
    /// per-chunk frame result for the live indicator.
    ///
    /// - Returns: `false` when the session could not be opened, in which case
    ///   the caller must not start audio capture.
    private func startDetectionStream() async -> Bool {
        let (stream, continuation) = AsyncStream<AudioInput>.makeStream()

        let events: AsyncThrowingStream<VadEvent, Error>
        do {
            events = try await RunAnywhere.vad.detectStream(stream)
        } catch {
            continuation.finish()
            logger.error("VAD stream failed to start: \(error.localizedDescription)")
            errorMessage = "VAD stream failed to start: \(error.localizedDescription)"
            return false
        }

        vadAudioContinuation = continuation
        detectionTask = Task { [weak self] in
            do {
                for try await event in events {
                    guard let self, !Task.isCancelled else { break }
                    switch event {
                    case .speechStarted:
                        self.isSpeechDetected = true
                        self.addLogEntry(.speechStarted)
                    case .speechEnded:
                        self.isSpeechDetected = false
                        self.addLogEntry(.speechEnded)
                    case .frame(let result):
                        self.isSpeechDetected = result.isSpeech
                    }
                }
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.logger.error("VAD stream failed: \(error.localizedDescription)")
                self.errorMessage = "VAD failed: \(error.localizedDescription)"
            }
        }
        return true
    }

    private func stopDetectionStream() {
        vadAudioContinuation?.finish()
        vadAudioContinuation = nil
        detectionTask?.cancel()
        detectionTask = nil
    }

    private func addLogEntry(_ type: SpeechActivityLogEntry.ActivityType) {
        let entry = SpeechActivityLogEntry(type: type, timestamp: Date())
        activityLog.insert(entry, at: 0) // Most recent first

        // Keep log manageable
        if activityLog.count > 50 {
            activityLog.removeLast()
        }
    }

    // MARK: - Cleanup

    func cleanup() {
        audioCapture.stopRecording()
        stopDetectionStream()
        hasSubscribedToAudioLevel = false
        cleanupBase()
    }
}

// MARK: - Supporting Types

/// A single entry in the speech activity log
struct SpeechActivityLogEntry: Identifiable {
    let id = UUID()
    let type: ActivityType
    let timestamp: Date

    enum ActivityType {
        case speechStarted
        case speechEnded

        var label: String {
            switch self {
            case .speechStarted: return "Speech Started"
            case .speechEnded: return "Speech Ended"
            }
        }

        var icon: String {
            switch self {
            case .speechStarted: return "mic.fill"
            case .speechEnded: return "mic.slash"
            }
        }
    }
}
