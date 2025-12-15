import Foundation
import RunAnywhere
import AVFoundation
import Combine
import os

@MainActor
class VoiceAssistantViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "VoiceAssistantViewModel")
    private let audioCapture = AudioCaptureManager()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Published Properties
    @Published var currentTranscript: String = ""
    @Published var assistantResponse: String = ""
    @Published var isProcessing: Bool = false
    @Published var errorMessage: String?
    @Published var isInitialized = false
    @Published var currentStatus = "Initializing..."
    @Published var currentLLMModel: String = ""
    @Published var whisperModel: String = "Whisper Base"
    @Published var isListening: Bool = false
    @Published var audioLevel: Float = 0.0

    // MARK: - Model Selection State (for Voice Pipeline Setup)
    @Published var sttModel: (framework: InferenceFramework, name: String)?
    @Published var llmModel: (framework: InferenceFramework, name: String)?
    @Published var ttsModel: (framework: InferenceFramework, name: String)?

    // MARK: - Model Loading State (using ModelLoadState for UI compatibility)
    @Published var sttModelState: ModelLoadState = .notLoaded
    @Published var llmModelState: ModelLoadState = .notLoaded
    @Published var ttsModelState: ModelLoadState = .notLoaded

    /// Check if all required models are selected for the voice pipeline
    var allModelsReady: Bool {
        sttModel != nil && llmModel != nil && ttsModel != nil
    }

    /// Check if all models are actually loaded in memory
    var allModelsLoaded: Bool {
        sttModelState.isLoaded && llmModelState.isLoaded && ttsModelState.isLoaded
    }

    // Session state for UI
    enum SessionState: Equatable {
        case disconnected
        case connecting
        case connected
        case listening
        case processing
        case speaking
        case error(String)

        static func == (lhs: SessionState, rhs: SessionState) -> Bool {
            switch (lhs, rhs) {
            case (.disconnected, .disconnected),
                 (.connecting, .connecting),
                 (.connected, .connected),
                 (.listening, .listening),
                 (.processing, .processing),
                 (.speaking, .speaking):
                return true
            case (.error(let lhsMessage), .error(let rhsMessage)):
                return lhsMessage == rhsMessage
            default:
                return false
            }
        }
    }
    @Published var sessionState: SessionState = .disconnected
    @Published var isSpeechDetected: Bool = false

    // MARK: - Pipeline State
    private var pipelineTask: Task<Void, Never>?
    private var recordedAudioData: Data = Data()

    // MARK: - Initialization

    func initialize() async {
        logger.info("Initializing VoiceAssistantViewModel...")

        // Request microphone permission
        logger.info("Requesting microphone permission...")
        let hasPermission = await audioCapture.requestPermission()
        logger.info("Microphone permission: \(hasPermission)")
        guard hasPermission else {
            currentStatus = "Microphone permission denied"
            errorMessage = "Please enable microphone access in Settings"
            logger.error("Microphone permission denied")
            return
        }

        // Subscribe to audio level updates
        audioCapture.$audioLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                self?.audioLevel = level
            }
            .store(in: &cancellables)

        // Get current LLM model info
        updateModelInfo()

        // Listen for model changes
        NotificationCenter.default.addObserver(
            forName: Notification.Name("ModelLoaded"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateModelInfo()
            }
        }

        // Subscribe to SDK events for model loading state
        subscribeToSDKEvents()

        logger.info("Voice assistant initialized")
        currentStatus = "Ready to listen"
        isInitialized = true
    }

    /// Subscribe to SDK events for model state updates
    private func subscribeToSDKEvents() {
        RunAnywhere.events.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handleSDKEvent(event)
            }
            .store(in: &cancellables)

        // Check initial model states
        Task {
            let isLoaded = await RunAnywhere.isModelLoaded
            llmModelState = isLoaded ? .loaded : .notLoaded
            if let modelId = await RunAnywhere.getCurrentModelId(),
               let model = ModelListViewModel.shared.availableModels.first(where: { $0.id == modelId }) {
                llmModel = (framework: model.preferredFramework ?? .llamaCpp, name: model.name)
                currentLLMModel = model.name
            }
        }
    }

    private func handleSDKEvent(_ event: any SDKEvent) {
        if let llmEvent = event as? LLMEvent {
            switch llmEvent {
            case .modelLoadCompleted(let modelId, _, _):
                llmModelState = .loaded
                if let model = ModelListViewModel.shared.availableModels.first(where: { $0.id == modelId }) {
                    llmModel = (framework: model.preferredFramework ?? .llamaCpp, name: model.name)
                    currentLLMModel = model.name
                }
            case .modelUnloaded:
                llmModelState = .notLoaded
            case .modelLoadStarted:
                llmModelState = .loading
            default:
                break
            }
        }
    }

    private func updateModelInfo() {
        Task {
            if let modelId = await RunAnywhere.getCurrentModelId(),
               let model = ModelListViewModel.shared.availableModels.first(where: { $0.id == modelId }) {
                currentLLMModel = model.name
                llmModelState = .loaded
                llmModel = (framework: model.preferredFramework ?? .llamaCpp, name: model.name)
                logger.info("Using LLM model: \(self.currentLLMModel)")
            } else {
                currentLLMModel = "No model loaded"
                llmModelState = .notLoaded
                logger.info("No LLM model currently loaded")
            }
        }
    }

    // MARK: - Model Selection for Voice Pipeline

    /// Set the STT model for voice pipeline
    func setSTTModel(_ model: ModelInfo) {
        sttModel = (framework: model.preferredFramework ?? .onnx, name: model.name)
        whisperModel = model.name
        sttModelState = model.isDownloaded ? .loaded : .notLoaded
        logger.info("Set STT model: \(model.name)")
    }

    /// Set the LLM model for voice pipeline
    func setLLMModel(_ model: ModelInfo) {
        llmModel = (framework: model.preferredFramework ?? .llamaCpp, name: model.name)
        currentLLMModel = model.name
        logger.info("Set LLM model: \(model.name)")
    }

    /// Set the TTS model for voice pipeline
    func setTTSModel(_ model: ModelInfo) {
        ttsModel = (framework: model.preferredFramework ?? .onnx, name: model.name)
        ttsModelState = model.isDownloaded ? .loaded : .notLoaded
        logger.info("Set TTS model: \(model.name)")
    }

    // MARK: - Conversation Control

    /// Start real-time conversation using SDK's VoiceAgent
    func startConversation() async {
        logger.info("Starting conversation with VoiceAgent...")

        guard allModelsReady else {
            sessionState = .error("All models must be selected before starting")
            currentStatus = "Error"
            errorMessage = "Please select all required models (STT, LLM, TTS) before starting"
            logger.error("Cannot start conversation: not all models selected")
            return
        }

        sessionState = .connecting
        currentStatus = "Initializing voice agent..."

        do {
            // Initialize the voice agent with selected models
            // Use model names/IDs for initialization
            try await RunAnywhere.initializeVoiceAgent(
                sttModelId: sttModel?.name ?? "",
                llmModelId: llmModel?.name ?? "",
                ttsVoice: ttsModel?.name ?? "com.apple.ttsbundle.siri_female_en-US_compact"
            )

            sessionState = .listening
            isListening = true
            currentStatus = "Listening..."
            errorMessage = nil

            logger.info("Voice agent initialized and listening")
        } catch {
            sessionState = .error("Failed to initialize: \(error.localizedDescription)")
            currentStatus = "Error"
            errorMessage = "Failed to initialize voice agent: \(error.localizedDescription)"
            logger.error("Failed to initialize voice agent: \(error)")
        }
    }

    /// Start recording audio for voice turn
    func startRecording() async throws {
        guard isListening || sessionState == .connected else {
            throw NSError(domain: "VoiceAssistant", code: 1, userInfo: [NSLocalizedDescriptionKey: "Voice agent not started"])
        }

        sessionState = .listening
        currentStatus = "Listening..."
        isSpeechDetected = true
        recordedAudioData = Data()

        // Start capturing audio
        try audioCapture.startRecording { [weak self] audioData in
            Task { @MainActor in
                self?.recordedAudioData.append(audioData)
            }
        }

        logger.info("Recording started")
    }

    /// Stop recording and process the voice turn
    func stopRecordingAndProcess() async throws {
        logger.info("Stopping recording and processing...")

        // Stop audio capture
        audioCapture.stopRecording()
        isSpeechDetected = false

        guard !recordedAudioData.isEmpty else {
            logger.warning("No audio data captured")
            return
        }

        sessionState = .processing
        currentStatus = "Processing..."
        isProcessing = true

        do {
            // Process the voice turn through SDK
            let result = try await RunAnywhere.processVoiceTurn(recordedAudioData)

            if result.speechDetected {
                currentTranscript = result.transcription ?? ""
                assistantResponse = result.response ?? ""

                logger.info("Transcription: \(result.transcription ?? "")")
                logger.info("Response: \(result.response ?? "")")

                // Handle synthesized audio if available
                if result.synthesizedAudio != nil {
                    sessionState = .speaking
                    currentStatus = "Speaking..."
                    // Audio playback would be handled here
                }
            } else {
                logger.info("No speech detected in audio")
            }

            sessionState = .listening
            currentStatus = "Listening..."
            isProcessing = false

        } catch {
            sessionState = .error(error.localizedDescription)
            currentStatus = "Error"
            errorMessage = error.localizedDescription
            isProcessing = false
            logger.error("Voice processing error: \(error)")
            throw error
        }
    }

    /// Stop conversation
    func stopConversation() async {
        logger.info("Stopping conversation...")

        isListening = false
        isProcessing = false
        isSpeechDetected = false

        // Cancel pipeline task
        pipelineTask?.cancel()
        pipelineTask = nil

        // Stop audio capture
        audioCapture.stopRecording()

        // Cleanup voice agent
        await RunAnywhere.cleanupVoiceAgent()

        // Reset UI state
        currentStatus = "Ready to listen"
        sessionState = .disconnected
        errorMessage = nil
        recordedAudioData = Data()

        logger.info("Conversation stopped")
    }

    /// Interrupt AI response
    func interruptResponse() async {
        await stopConversation()
    }

    /// Speak response using TTS
    func speakResponse(_ text: String) async {
        logger.info("Speaking response: '\(text, privacy: .public)'")

        do {
            let audioData = try await RunAnywhere.voiceAgentSynthesizeSpeech(text)
            // Play the audio data using AVAudioPlayer or similar
            logger.info("Speech synthesized, \(audioData.count) bytes")
        } catch {
            logger.error("TTS error: \(error)")
        }
    }
}
