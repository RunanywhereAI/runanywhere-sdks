import Foundation
import RunAnywhere
import AVFoundation
import Combine
import os

@MainActor
class VoiceAssistantViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "VoiceAssistantViewModel")
    private let audioCapture = AudioCaptureManager()
    private let audioPlayback = AudioPlaybackManager()
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
    // Store both name (for display) and ID (for SDK operations)
    @Published var sttModel: (framework: InferenceFramework, name: String, id: String)?
    @Published var llmModel: (framework: InferenceFramework, name: String, id: String)?
    @Published var ttsModel: (framework: InferenceFramework, name: String, id: String)?

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

    /// Convert SDK ComponentLoadState to local ModelLoadState
    private func toModelLoadState(_ state: ComponentLoadState) -> ModelLoadState {
        switch state {
        case .notLoaded:
            return .notLoaded
        case .loading:
            return .loading
        case .loaded:
            return .loaded
        case .error(let message):
            return .error(message)
        }
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
    private var isCapturingAudio = false
    private var lastSpeechTime: Date?
    private let silenceThreshold: TimeInterval = 1.5 // seconds of silence to end turn
    private var speechDetectionTimer: Timer?

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

        // Check initial model states from SDK
        refreshComponentStatesFromSDK()
    }

    /// Refresh all component states from the SDK
    /// Call this on init and when returning to the voice assistant view
    func refreshComponentStatesFromSDK() {
        Task {
            logger.info("Refreshing component states from SDK...")

            // Use the new unified SDK API to get all component states at once
            let componentStates = await RunAnywhere.getVoiceAgentComponentStates()

            // Update STT state
            sttModelState = toModelLoadState(componentStates.stt)
            if case .loaded(let modelId) = componentStates.stt {
                if let model = ModelListViewModel.shared.availableModels.first(where: { $0.id == modelId }) {
                    sttModel = (framework: model.preferredFramework ?? .whisperKit, name: model.name, id: modelId)
                    whisperModel = model.name
                    logger.info("STT model loaded: \(model.name) (id: \(modelId))")
                } else {
                    // Model ID exists but not in our list - still mark as loaded
                    sttModel = (framework: .whisperKit, name: modelId, id: modelId)
                    whisperModel = modelId
                    logger.info("STT model loaded (external): \(modelId)")
                }
            }

            // Update LLM state
            llmModelState = toModelLoadState(componentStates.llm)
            if case .loaded(let modelId) = componentStates.llm {
                if let model = ModelListViewModel.shared.availableModels.first(where: { $0.id == modelId }) {
                    llmModel = (framework: model.preferredFramework ?? .llamaCpp, name: model.name, id: modelId)
                    currentLLMModel = model.name
                    logger.info("LLM model loaded: \(model.name) (id: \(modelId))")
                } else {
                    llmModel = (framework: .llamaCpp, name: modelId, id: modelId)
                    currentLLMModel = modelId
                    logger.info("LLM model loaded (external): \(modelId)")
                }
            }

            // Update TTS state
            ttsModelState = toModelLoadState(componentStates.tts)
            if case .loaded(let voiceId) = componentStates.tts {
                // For TTS, the voice ID might be a system voice or a custom model
                if let model = ModelListViewModel.shared.availableModels.first(where: { $0.id == voiceId }) {
                    ttsModel = (framework: model.preferredFramework ?? .onnx, name: model.name, id: voiceId)
                    logger.info("TTS model loaded: \(model.name) (id: \(voiceId))")
                } else {
                    // System voice or external voice
                    ttsModel = (framework: .onnx, name: voiceId, id: voiceId)
                    logger.info("TTS voice loaded: \(voiceId)")
                }
            }

            logger.info("Component states refreshed - STT: \(self.sttModelState.isLoaded), LLM: \(self.llmModelState.isLoaded), TTS: \(self.ttsModelState.isLoaded)")
        }
    }

    private func handleSDKEvent(_ event: any SDKEvent) {
        // Handle LLM events
        if let llmEvent = event as? LLMEvent {
            switch llmEvent {
            case .modelLoadCompleted(let modelId, _, _):
                llmModelState = .loaded
                if let model = ModelListViewModel.shared.availableModels.first(where: { $0.id == modelId }) {
                    llmModel = (framework: model.preferredFramework ?? .llamaCpp, name: model.name, id: modelId)
                    currentLLMModel = model.name
                } else {
                    llmModel = (framework: .llamaCpp, name: modelId, id: modelId)
                    currentLLMModel = modelId
                }
                logger.info("LLM model load completed: \(modelId)")
            case .modelUnloaded:
                llmModelState = .notLoaded
                llmModel = nil
                currentLLMModel = ""
                logger.info("LLM model unloaded")
            case .modelLoadStarted:
                llmModelState = .loading
                logger.info("LLM model loading started")
            case .modelLoadFailed(_, let error, _):
                llmModelState = .error(error)
                logger.error("LLM model load failed: \(error)")
            default:
                break
            }
        }

        // Handle STT events
        if let sttEvent = event as? STTEvent {
            switch sttEvent {
            case .modelLoadCompleted(let modelId, _, _):
                sttModelState = .loaded
                if let model = ModelListViewModel.shared.availableModels.first(where: { $0.id == modelId }) {
                    sttModel = (framework: model.preferredFramework ?? .whisperKit, name: model.name, id: modelId)
                    whisperModel = model.name
                } else {
                    sttModel = (framework: .whisperKit, name: modelId, id: modelId)
                    whisperModel = modelId
                }
                logger.info("STT model load completed: \(modelId)")
            case .modelUnloaded:
                sttModelState = .notLoaded
                sttModel = nil
                whisperModel = ""
                logger.info("STT model unloaded")
            case .modelLoadStarted:
                sttModelState = .loading
                logger.info("STT model loading started")
            case .modelLoadFailed(_, let error, _):
                sttModelState = .error(error)
                logger.error("STT model load failed: \(error)")
            default:
                break
            }
        }

        // Handle TTS events
        if let ttsEvent = event as? TTSEvent {
            switch ttsEvent {
            case .modelLoadCompleted(let voiceId, _, _):
                ttsModelState = .loaded
                if let model = ModelListViewModel.shared.availableModels.first(where: { $0.id == voiceId }) {
                    ttsModel = (framework: model.preferredFramework ?? .onnx, name: model.name, id: voiceId)
                } else {
                    ttsModel = (framework: .onnx, name: voiceId, id: voiceId)
                }
                logger.info("TTS voice load completed: \(voiceId)")
            case .modelUnloaded:
                ttsModelState = .notLoaded
                ttsModel = nil
                logger.info("TTS voice unloaded")
            case .modelLoadStarted:
                ttsModelState = .loading
                logger.info("TTS voice loading started")
            case .modelLoadFailed(_, let error, _):
                ttsModelState = .error(error)
                logger.error("TTS voice load failed: \(error)")
            default:
                break
            }
        }
    }

    private func updateModelInfo() {
        // Refresh all component states from SDK to get accurate in-memory states
        refreshComponentStatesFromSDK()
    }

    // MARK: - Model Selection for Voice Pipeline

    /// Set the STT model for voice pipeline
    /// Note: This sets the selection, but the actual load state comes from SDK events
    func setSTTModel(_ model: ModelInfo) {
        sttModel = (framework: model.preferredFramework ?? .whisperKit, name: model.name, id: model.id)
        whisperModel = model.name
        logger.info("Selected STT model: \(model.name) (id: \(model.id))")

        // Check if this model is already loaded in SDK
        Task {
            let states = await RunAnywhere.getVoiceAgentComponentStates()
            if case .loaded(let loadedId) = states.stt, loadedId == model.id {
                sttModelState = .loaded
                logger.info("STT model \(model.name) is already loaded in SDK")
            } else {
                // Model selected but not loaded yet - will need to be loaded when starting voice
                sttModelState = .notLoaded
            }
        }
    }

    /// Set the LLM model for voice pipeline
    /// Note: This sets the selection, but the actual load state comes from SDK events
    func setLLMModel(_ model: ModelInfo) {
        llmModel = (framework: model.preferredFramework ?? .llamaCpp, name: model.name, id: model.id)
        currentLLMModel = model.name
        logger.info("Selected LLM model: \(model.name) (id: \(model.id))")

        // Check if this model is already loaded in SDK
        Task {
            let states = await RunAnywhere.getVoiceAgentComponentStates()
            if case .loaded(let loadedId) = states.llm, loadedId == model.id {
                llmModelState = .loaded
                logger.info("LLM model \(model.name) is already loaded in SDK")
            } else {
                llmModelState = .notLoaded
            }
        }
    }

    /// Set the TTS model for voice pipeline
    /// Note: This sets the selection, but the actual load state comes from SDK events
    func setTTSModel(_ model: ModelInfo) {
        ttsModel = (framework: model.preferredFramework ?? .onnx, name: model.name, id: model.id)
        logger.info("Selected TTS model: \(model.name) (id: \(model.id))")

        // Check if this model/voice is already loaded in SDK
        Task {
            let states = await RunAnywhere.getVoiceAgentComponentStates()
            if case .loaded(let loadedId) = states.tts, loadedId == model.id {
                ttsModelState = .loaded
                logger.info("TTS model \(model.name) is already loaded in SDK")
            } else {
                ttsModelState = .notLoaded
            }
        }
    }

    // MARK: - Conversation Control

    /// Start real-time conversation using SDK's VoiceAgent
    func startConversation() async {
        logger.info("Starting conversation with VoiceAgent...")

        // Check if all models are loaded (not just selected)
        guard allModelsLoaded else {
            sessionState = .error("All models must be loaded before starting")
            currentStatus = "Error"
            errorMessage = "Please ensure all models (STT, LLM, TTS) are loaded before starting"
            logger.error("Cannot start conversation: not all models loaded. STT: \(self.sttModelState.isLoaded), LLM: \(self.llmModelState.isLoaded), TTS: \(self.ttsModelState.isLoaded)")
            return
        }

        sessionState = .connecting
        currentStatus = "Initializing voice agent..."

        do {
            // Since all models are already loaded, use the new API that reuses them
            // This avoids reloading and uses the pre-loaded models
            try await RunAnywhere.initializeVoiceAgentWithLoadedModels()

            // Start audio capture immediately after initialization
            try startAudioCapture()

            sessionState = .listening
            isListening = true
            currentStatus = "Listening..."
            errorMessage = nil

            logger.info("Voice agent initialized with pre-loaded models and listening")
        } catch {
            sessionState = .error("Failed to initialize: \(error.localizedDescription)")
            currentStatus = "Error"
            errorMessage = "Failed to initialize voice agent: \(error.localizedDescription)"
            logger.error("Failed to initialize voice agent: \(error)")
        }
    }

    /// Start capturing audio from microphone
    private func startAudioCapture() throws {
        guard !isCapturingAudio else {
            logger.warning("Already capturing audio")
            return
        }

        recordedAudioData = Data()
        lastSpeechTime = nil
        isSpeechDetected = false

        // Start capturing audio
        try audioCapture.startRecording { [weak self] audioData in
            guard let self = self else { return }

            Task { @MainActor in
                // Accumulate audio data
                self.recordedAudioData.append(audioData)

                // Simple energy-based speech detection using audio level
                // The AudioCaptureManager already calculates and publishes audioLevel
                let currentLevel = self.audioLevel

                // Threshold for speech detection (adjust based on testing)
                let speechThreshold: Float = 0.1

                if currentLevel > speechThreshold {
                    // Speech detected
                    if !self.isSpeechDetected {
                        self.logger.info("Speech started (level: \(currentLevel))")
                        self.isSpeechDetected = true
                    }
                    self.lastSpeechTime = Date()
                } else if self.isSpeechDetected {
                    // Check if silence duration exceeded threshold
                    if let lastSpeech = self.lastSpeechTime,
                       Date().timeIntervalSince(lastSpeech) > self.silenceThreshold {
                        // Speech ended - process the turn
                        self.logger.info("Speech ended after \(self.silenceThreshold)s silence")
                        self.isSpeechDetected = false

                        // Only process if we have enough audio data
                        if self.recordedAudioData.count > 16000 * 2 { // at least ~0.5s of 16kHz mono int16 audio
                            Task {
                                await self.processCurrentAudio()
                            }
                        } else {
                            self.logger.info("Not enough audio data to process: \(self.recordedAudioData.count) bytes")
                            self.recordedAudioData = Data()
                        }
                    }
                }
            }
        }

        isCapturingAudio = true
        logger.info("Audio capture started")
    }

    /// Stop audio capture
    private func stopAudioCapture() {
        guard isCapturingAudio else { return }

        audioCapture.stopRecording()
        isCapturingAudio = false
        isSpeechDetected = false
        lastSpeechTime = nil
        speechDetectionTimer?.invalidate()
        speechDetectionTimer = nil

        logger.info("Audio capture stopped")
    }

    /// Process the currently accumulated audio
    private func processCurrentAudio() async {
        let audioToProcess = recordedAudioData
        recordedAudioData = Data() // Clear for next turn

        guard !audioToProcess.isEmpty else {
            logger.warning("No audio data to process")
            return
        }

        logger.info("Processing \(audioToProcess.count) bytes of audio")

        sessionState = .processing
        currentStatus = "Processing..."
        isProcessing = true

        do {
            // Process the voice turn through SDK
            let result = try await RunAnywhere.processVoiceTurn(audioToProcess)

            if result.speechDetected {
                currentTranscript = result.transcription ?? ""
                assistantResponse = result.response ?? ""

                logger.info("Transcription: \(result.transcription ?? "")")
                logger.info("Response: \(result.response ?? "")")

                // Handle synthesized audio if available
                if let audioData = result.synthesizedAudio, !audioData.isEmpty {
                    sessionState = .speaking
                    currentStatus = "Speaking..."
                    logger.info("Synthesized audio: \(audioData.count) bytes")

                    // Stop audio capture while playing to avoid feedback
                    stopAudioCapture()

                    // Play the synthesized audio
                    await playAudio(audioData)

                    // Resume audio capture after playback
                    try? startAudioCapture()
                }
            } else {
                logger.info("No speech detected in audio")
            }

            // Return to listening state
            sessionState = .listening
            currentStatus = "Listening..."
            isProcessing = false

        } catch {
            logger.error("Voice processing error: \(error)")
            // Don't set error state, just log and continue listening
            sessionState = .listening
            currentStatus = "Listening..."
            isProcessing = false
        }
    }

    /// Manually trigger processing of current audio (for push-to-talk mode)
    /// This can be called when user wants to send their message manually
    func sendCurrentAudio() async {
        guard isCapturingAudio else {
            logger.warning("Not capturing audio")
            return
        }

        // Force process whatever audio we have
        isSpeechDetected = false
        await processCurrentAudio()
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

        // Stop audio capture using our helper method
        stopAudioCapture()

        // Cleanup voice agent
        await RunAnywhere.cleanupVoiceAgent()

        // Reset UI state
        currentStatus = "Ready to listen"
        sessionState = .disconnected
        errorMessage = nil
        recordedAudioData = Data()
        audioLevel = 0.0

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
            logger.info("Speech synthesized, \(audioData.count) bytes")
            await playAudio(audioData)
        } catch {
            logger.error("TTS error: \(error)")
        }
    }

    /// Play audio data using SDK's AudioPlaybackManager
    /// The TTS output from the SDK is already a proper WAV file (16-bit PCM with headers)
    private func playAudio(_ audioData: Data) async {
        guard !audioData.isEmpty else {
            logger.warning("Empty audio data, skipping playback")
            return
        }

        logger.info("Playing audio: \(audioData.count) bytes")

        do {
            try await audioPlayback.play(audioData)
            logger.info("Audio playback completed")
        } catch {
            logger.error("Failed to play audio: \(error)")
        }
    }

    /// Stop any ongoing audio playback
    func stopPlayback() {
        audioPlayback.stop()
    }
}
