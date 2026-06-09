import Foundation
import RunAnywhere
import Combine
import os

/// ViewModel for Voice Activity Detection functionality
/// Manages microphone capture, VAD model loading, and real-time speech detection
@MainActor
class VADViewModel: VoiceComponentViewModelBase {
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

    /// Mic chunks are fed straight into the SDK's `streamVAD` session; the
    /// SDK owns model framing — no app-side buffer math.
    private var vadAudioContinuation: AsyncStream<Data>.Continuation?
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

        startDetectionStream()

        do {
            try await AudioCapturePump.startRecording(with: audioCapture) { [weak self] audioData in
                guard let self else { return }
                // SDK expects Float32 PCM; framing is handled natively.
                self.vadAudioContinuation?.yield(RunAnywhere.pcm16ToFloat32(audioData))
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

    /// Consume the SDK's streaming VAD session: one `RAVADResult` per mic
    /// chunk, with speech-state transitions logged for the activity list.
    private func startDetectionStream() {
        let (stream, continuation) = AsyncStream<Data>.makeStream()
        vadAudioContinuation = continuation

        detectionTask = Task { [weak self] in
            var wasSpeechActive = false

            for await result in RunAnywhere.streamVAD(audio: stream) {
                guard let self, !Task.isCancelled else { break }

                if !result.errorMessage.isEmpty {
                    self.logger.error("VAD processing error: \(result.errorMessage)")
                    continue
                }

                let speechDetected = result.isSpeech
                self.isSpeechDetected = speechDetected

                // Log state transitions
                if speechDetected && !wasSpeechActive {
                    self.addLogEntry(.speechStarted)
                    wasSpeechActive = true
                } else if !speechDetected && wasSpeechActive {
                    self.addLogEntry(.speechEnded)
                    wasSpeechActive = false
                }
            }
        }
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
