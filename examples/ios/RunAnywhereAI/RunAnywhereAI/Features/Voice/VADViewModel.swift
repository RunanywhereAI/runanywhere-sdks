import Foundation
import RunAnywhere
import Combine
import os

/// ViewModel for Voice Activity Detection functionality
/// Manages microphone capture, VAD model loading, and real-time speech detection
@MainActor
class VADViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.runanywhere", category: "VAD")
    private let audioCapture = AudioCaptureManager()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Published Properties (UI State)

    @Published var selectedFramework: InferenceFramework?
    @Published var selectedModelName: String?
    @Published var selectedModelId: String?
    @Published var isListening = false
    @Published var isProcessing = false
    @Published var isSpeechDetected = false
    @Published var audioLevel: Float = 0.0
    @Published var errorMessage: String?

    /// Log of speech activity events with timestamps
    @Published var activityLog: [SpeechActivityLogEntry] = []

    // MARK: - Private Properties

    private var audioBuffer = Data()
    private var detectionTask: Task<Void, Never>?
    private var isInitialized = false
    private var hasSubscribedToAudioLevel = false
    private var hasSubscribedToSDKEvents = false

    // MARK: - Initialization

    init() {
        logger.debug("VADViewModel initialized")
    }

    /// Initialize the ViewModel - request permissions and setup subscriptions
    func initialize() async {
        guard !isInitialized else {
            logger.debug("VAD view model already initialized, skipping")
            return
        }
        isInitialized = true

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
        logger.info("Loading VAD model from selection: \(model.name)")
        isProcessing = true
        errorMessage = nil

        do {
            var loadRequest = RAModelLoadRequest()
            loadRequest.modelID = model.id
            loadRequest.category = .voiceActivityDetection
            let loadResult = await RunAnywhere.loadModel(loadRequest)
            guard loadResult.success else {
                throw SDKException(code: .unknown, message: loadResult.errorMessage, category: .internal)
            }
            selectedFramework = model.framework
            selectedModelName = model.name.modelNameFromID()
            selectedModelId = model.id
            logger.info("VAD model loaded successfully: \(model.name)")
        } catch {
            logger.error("Failed to load VAD model: \(error.localizedDescription)")
            errorMessage = "Failed to load model: \(error.localizedDescription)"
        }

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

    private func subscribeToSDKEvents() {
        guard !hasSubscribedToSDKEvents else {
            logger.debug("Already subscribed to SDK events, skipping")
            return
        }
        hasSubscribedToSDKEvents = true

        RunAnywhere.events.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                Task { @MainActor in
                    self?.handleSDKEvent(event)
                }
            }
            .store(in: &cancellables)
    }

    private func handleSDKEvent(_ event: RASDKEvent) {
        guard event.category == .vad || event.component == .vad else { return }

        let modelId = event.model.modelID

        switch event.model.kind {
        case .loadCompleted:
            selectedModelId = modelId
            if let matchingModel = ModelListViewModel.shared.availableModels.first(where: { $0.id == modelId }) {
                selectedModelName = matchingModel.name
                selectedFramework = matchingModel.framework
            } else {
                selectedModelName = modelId.modelNameFromID()
            }
            logger.info("VAD model loaded: \(modelId)")
        case .unloadCompleted:
            selectedModelId = nil
            selectedModelName = nil
            selectedFramework = nil
            logger.info("VAD model unloaded")
        default:
            break
        }
    }

    private func checkInitialModelState() async {
        var req = RACurrentModelRequest()
        req.category = .voiceActivityDetection
        let snapshot = RunAnywhere.currentModel(req)
        if snapshot.found {
            let model = snapshot.model
            selectedModelId = model.id
            selectedModelName = model.name.modelNameFromID()
            selectedFramework = model.framework
            logger.info("VAD model already loaded: \(model.name)")
        }
    }

    // MARK: - Private Methods - Listening

    private func startListening() async {
        logger.info("Starting VAD listening")
        errorMessage = nil
        audioBuffer = Data()
        isSpeechDetected = false

        guard selectedModelId != nil else {
            errorMessage = "No VAD model loaded"
            return
        }

        // VAD is initialized implicitly by loading the VAD model.
        // The canonical SDK API does not expose an explicit readiness check.
        do {
            try await audioCapture.startRecording { [weak self] audioData in
                Task { @MainActor in
                    self?.audioBuffer.append(audioData)
                }
            }

            isListening = true
            startDetectionLoop()
            logger.info("VAD listening started")
        } catch {
            logger.error("Failed to start recording: \(error.localizedDescription)")
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
        }
    }

    private func stopListening() async {
        logger.info("Stopping VAD listening")

        detectionTask?.cancel()
        detectionTask = nil

        audioCapture.stopRecording()

        isListening = false
        isSpeechDetected = false
        audioLevel = 0.0
    }

    /// Continuously process audio chunks through the VAD model
    private func startDetectionLoop() {
        detectionTask = Task { [weak self] in
            var wasSpeechActive = false

            while !Task.isCancelled {
                guard let self = self, self.isListening else { break }

                // Process audio buffer if we have enough data (512 samples at 16kHz = 32ms)
                let bufferData = self.audioBuffer
                if bufferData.count >= 1024 { // 512 Int16 samples = 1024 bytes
                    self.audioBuffer = Data() // Clear buffer

                    let audioBytes = RunAnywhere.pcm16ToFloat32(bufferData)

                    do {
                        let vadResult = try await RunAnywhere.detectVoiceActivity(audioBytes)
                        let speechDetected = vadResult.isSpeech

                        self.isSpeechDetected = speechDetected

                        // Log state transitions
                        if speechDetected && !wasSpeechActive {
                            self.addLogEntry(.speechStarted)
                            wasSpeechActive = true
                        } else if !speechDetected && wasSpeechActive {
                            self.addLogEntry(.speechEnded)
                            wasSpeechActive = false
                        }
                    } catch {
                        self.logger.error("VAD processing error: \(error.localizedDescription)")
                    }
                }

                try? await Task.sleep(nanoseconds: 30_000_000) // 30ms
            }
        }
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
        detectionTask?.cancel()
        detectionTask = nil
        cancellables.removeAll()
        isInitialized = false
        hasSubscribedToAudioLevel = false
        hasSubscribedToSDKEvents = false
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
