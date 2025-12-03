import Foundation
import RunAnywhere
import AVFoundation
import Combine
import os

@MainActor
class VoiceAssistantViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "VoiceAssistantViewModel")
    private let audioCapture = AudioCapture()
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
    @Published var audioLevel: Float = 0.0  // For audio level visualization

    // MARK: - Model Selection State (for Voice Pipeline Setup)
    @Published var sttModel: (framework: LLMFramework, name: String)?
    @Published var llmModel: (framework: LLMFramework, name: String)?
    @Published var ttsModel: (framework: LLMFramework, name: String)?

    // MARK: - Model Loading State (from SDK lifecycle tracker)
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
    private var voicePipeline: ModularVoicePipeline?
    private var pipelineTask: Task<Void, Never>?

    /// Get the currently loaded STT model ID from the SDK lifecycle tracker
    private var currentSTTModelId: String? {
        ModelLifecycleTracker.shared.modelsByModality[.stt]?.modelId
    }

    /// Get the currently loaded LLM model ID from the SDK lifecycle tracker
    private var currentLLMModelId: String? {
        ModelLifecycleTracker.shared.modelsByModality[.llm]?.modelId
    }

    /// Get the currently loaded TTS model ID from the SDK lifecycle tracker
    private var currentTTSModelId: String? {
        ModelLifecycleTracker.shared.modelsByModality[.tts]?.modelId
    }

    // MARK: - Initialization

    func initialize() async {
        logger.info("Initializing VoiceAssistantViewModel...")

        // Request microphone permission
        logger.info("Requesting microphone permission...")
        let hasPermission = await AudioCapture.requestMicrophonePermission()
        logger.info("Microphone permission: \(hasPermission)")
        guard hasPermission else {
            currentStatus = "Microphone permission denied"
            errorMessage = "Please enable microphone access in Settings"
            logger.error("Microphone permission denied")
            return
        }

        // Subscribe to model lifecycle changes from SDK
        subscribeToModelLifecycle()

        // Get current LLM model info
        updateModelInfo()

        // Listen for model changes (legacy support)
        NotificationCenter.default.addObserver(
            forName: Notification.Name("ModelLoaded"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.updateModelInfo()
            }
        }

        logger.info("Voice assistant initialized")
        currentStatus = "Ready to listen"
        isInitialized = true
    }

    /// Subscribe to SDK's model lifecycle tracker for real-time model state updates
    private func subscribeToModelLifecycle() {
        // Observe changes to loaded models via the SDK's lifecycle tracker
        ModelLifecycleTracker.shared.$modelsByModality
            .receive(on: DispatchQueue.main)
            .sink { [weak self] modelsByModality in
                guard let self = self else { return }

                // Update STT model state
                if let sttState = modelsByModality[.stt] {
                    self.sttModelState = sttState.state
                    if sttState.state.isLoaded {
                        self.sttModel = (framework: sttState.framework, name: sttState.modelName)
                        self.whisperModel = sttState.modelName
                        self.logger.info("✅ STT model loaded: \(sttState.modelName)")
                    }
                } else {
                    self.sttModelState = .notLoaded
                }

                // Update LLM model state
                if let llmState = modelsByModality[.llm] {
                    self.llmModelState = llmState.state
                    if llmState.state.isLoaded {
                        self.llmModel = (framework: llmState.framework, name: llmState.modelName)
                        self.currentLLMModel = llmState.modelName
                        self.logger.info("✅ LLM model loaded: \(llmState.modelName)")
                    }
                } else {
                    self.llmModelState = .notLoaded
                }

                // Update TTS model state
                if let ttsState = modelsByModality[.tts] {
                    self.ttsModelState = ttsState.state
                    if ttsState.state.isLoaded {
                        self.ttsModel = (framework: ttsState.framework, name: ttsState.modelName)
                        self.logger.info("✅ TTS model loaded: \(ttsState.modelName)")
                    }
                } else {
                    self.ttsModelState = .notLoaded
                }

                // Log overall state
                self.logger.info("📊 Voice pipeline state - STT: \(self.sttModelState.isLoaded), LLM: \(self.llmModelState.isLoaded), TTS: \(self.ttsModelState.isLoaded)")
            }
            .store(in: &cancellables)

        // Check initial state
        let modelsByModality = ModelLifecycleTracker.shared.modelsByModality
        if let sttState = modelsByModality[.stt] {
            sttModelState = sttState.state
            if sttState.state.isLoaded {
                sttModel = (framework: sttState.framework, name: sttState.modelName)
                whisperModel = sttState.modelName
            }
        }
        if let llmState = modelsByModality[.llm] {
            llmModelState = llmState.state
            if llmState.state.isLoaded {
                llmModel = (framework: llmState.framework, name: llmState.modelName)
                currentLLMModel = llmState.modelName
            }
        }
        if let ttsState = modelsByModality[.tts] {
            ttsModelState = ttsState.state
            if ttsState.state.isLoaded {
                ttsModel = (framework: ttsState.framework, name: ttsState.modelName)
            }
        }
    }

    private func updateModelInfo() {
        // Try ModelManager first
        if let model = ModelManager.shared.getCurrentModel() {
            currentLLMModel = model.name
            logger.info("Using LLM model from ModelManager: \(self.currentLLMModel)")
        }
        // Fallback to ModelListViewModel
        else if let model = ModelListViewModel.shared.currentModel {
            currentLLMModel = model.name
            logger.info("Using LLM model from ModelListViewModel: \(self.currentLLMModel)")
        }
        // Default if no model loaded
        else {
            currentLLMModel = "No model loaded"
            logger.info("No LLM model currently loaded")
        }
    }

    // MARK: - Model Selection for Voice Pipeline

    /// Set the STT model for voice pipeline
    func setSTTModel(_ model: ModelInfo) {
        sttModel = (framework: model.preferredFramework ?? .whisperKit, name: model.name)
        whisperModel = model.name
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
        logger.info("Set TTS model: \(model.name)")
    }

    // MARK: - Conversation Control

    /// Start real-time conversation using modular pipeline
    func startConversation() async {
        logger.info("Starting conversation with modular pipeline...")

        // Verify all required models are loaded before starting
        guard allModelsLoaded else {
            sessionState = .error("All models must be loaded before starting")
            currentStatus = "Error"
            errorMessage = "Please load all required models (STT, LLM, TTS) before starting the voice assistant"
            logger.error("Cannot start conversation: not all models are loaded")
            return
        }

        // Get the currently loaded model IDs from the SDK lifecycle tracker
        guard let sttModelId = currentSTTModelId else {
            sessionState = .error("No STT model loaded")
            errorMessage = "Please load a speech-to-text model first"
            logger.error("Cannot start conversation: no STT model loaded")
            return
        }

        guard let llmModelId = currentLLMModelId else {
            sessionState = .error("No LLM model loaded")
            errorMessage = "Please load a language model first"
            logger.error("Cannot start conversation: no LLM model loaded")
            return
        }

        // TTS is optional - use "system" as fallback
        let ttsModelId = currentTTSModelId ?? "system"

        logger.info("Starting voice pipeline with STT: \(sttModelId), LLM: \(llmModelId), TTS: \(ttsModelId)")

        sessionState = .connecting
        currentStatus = "Initializing components..."

        // Create pipeline configuration using the actually loaded models
        // NOTE: VAD removed for manual control mode - user taps to start/stop recording
        let config = ModularPipelineConfig(
            components: [.stt, .llm, .tts],  // No VAD - manual mode
            stt: VoiceSTTConfig(modelId: sttModelId),
            llm: VoiceLLMConfig(
                modelId: llmModelId,
                systemPrompt: "You are a helpful voice assistant. Keep responses concise and conversational.",
                maxTokens: 100  // Limit response to 100 tokens for concise voice interactions
            ),
            tts: VoiceTTSConfig(voice: ttsModelId)
        )

        // Create the pipeline
        do {
            voicePipeline = try await RunAnywhere.createVoicePipeline(config: config)
        } catch {
            sessionState = .error("Failed to create pipeline: \(error.localizedDescription)")
            currentStatus = "Error"
            errorMessage = "Failed to create voice pipeline: \(error.localizedDescription)"
            logger.error("Failed to create voice pipeline: \(error)")
            return
        }
        // ModularVoicePipeline uses events, not delegates

        // Initialize components first
        guard let pipeline = voicePipeline else {
            sessionState = .error("Failed to create pipeline")
            currentStatus = "Error"
            errorMessage = "Failed to create voice pipeline"
            return
        }

        // Initialize all components
        do {
            for try await event in pipeline.initializeComponents() {
                handleInitializationEvent(event)
            }
        } catch {
            sessionState = .error("Initialization failed: \(error.localizedDescription)")
            currentStatus = "Error"
            errorMessage = "Component initialization failed: \(error.localizedDescription)"
            logger.error("Component initialization failed: \(error)")
            return
        }

        // Start audio capture after initialization is complete
        let audioStream = audioCapture.startContinuousCapture()

        sessionState = .listening
        isListening = true
        currentStatus = "Listening..."
        errorMessage = nil

        // Process audio through pipeline
        pipelineTask = Task {
            do {
                for try await event in voicePipeline!.process(audioStream: audioStream) {
                    await handlePipelineEvent(event)
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Pipeline error: \(error.localizedDescription)"
                    self.sessionState = .error(error.localizedDescription)
                    self.isListening = false
                }
            }
        }

        logger.info("Conversation pipeline started")
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
        audioCapture.stopContinuousCapture()

        // Clean up pipeline
        voicePipeline = nil

        // Reset UI state
        currentStatus = "Ready to listen"
        sessionState = .disconnected
        errorMessage = nil

        logger.info("Conversation stopped")
    }

    /// Interrupt AI response
    func interruptResponse() async {
        // In the modular pipeline, we can stop and restart
        await stopConversation()
    }

    // MARK: - Initialization Event Handling

    @MainActor
    private func handleInitializationEvent(_ event: ModularPipelineEvent) {
        switch event {
        case .componentInitializing(let componentName):
            currentStatus = "Initializing \(componentName)..."
            logger.info("Initializing component: \(componentName)")

        case .componentInitialized(let componentName):
            currentStatus = "\(componentName) ready"
            logger.info("Component initialized: \(componentName)")

        case .componentInitializationFailed(let componentName, let error):
            sessionState = .error("Failed to initialize \(componentName)")
            currentStatus = "Error"
            errorMessage = "Failed to initialize \(componentName): \(error.localizedDescription)"
            logger.error("Component initialization failed for \(componentName): \(error)")

        case .allComponentsInitialized:
            currentStatus = "All components ready"
            logger.info("All components initialized successfully")

        default:
            break
        }
    }

    // MARK: - Pipeline Event Handling

    private func handlePipelineEvent(_ event: ModularPipelineEvent) async {
        await MainActor.run {
            switch event {
            case .vadAudioLevel(let level):
                // Update audio level for visualization
                audioLevel = level

            case .vadSpeechStart:
                sessionState = .listening
                currentStatus = "Listening..."
                isSpeechDetected = true
                isListening = true  // Ensure isListening is set for audio bars
                logger.info("Recording started")

            case .vadSpeechEnd:
                isSpeechDetected = false
                // Don't reset audioLevel immediately - let the UI fade out naturally
                // audioLevel = 0.0
                logger.info("Recording ended")

            case .sttPartialTranscript(let text):
                currentTranscript = text
                logger.info("Partial transcript: '\(text)'")

            case .sttFinalTranscript(let text):
                currentTranscript = text
                sessionState = .processing
                currentStatus = "Thinking..."
                isProcessing = true
                logger.info("Final transcript: '\(text)'")

            case .llmThinking:
                sessionState = .processing
                currentStatus = "Thinking..."
                assistantResponse = ""

            case .llmPartialResponse(let text):
                assistantResponse = text

            case .llmFinalResponse(let text):
                assistantResponse = text
                sessionState = .speaking
                currentStatus = "Speaking..."
                logger.info("AI Response: '\(text.prefix(50))...'")

            case .ttsStarted:
                sessionState = .speaking
                currentStatus = "Speaking..."

            case .ttsCompleted:
                sessionState = .listening
                currentStatus = "Listening..."
                isProcessing = false
                // Clear transcript for next interaction
                currentTranscript = ""

            case .audioControlPauseRecording:
                // Pause microphone to prevent TTS audio feedback loop
                logger.info("⏸️ Pausing microphone for TTS playback")
                audioCapture.pauseCapture()
                isListening = false
                audioLevel = 0.0

            case .audioControlResumeRecording:
                // Resume microphone after TTS playback completes
                logger.info("▶️ Resuming microphone after TTS")
                audioCapture.resumeCapture()
                isListening = true

            case .pipelineError(let error):
                errorMessage = error.localizedDescription
                sessionState = .error(error.localizedDescription)
                isProcessing = false
                isListening = false
                logger.error("Pipeline error: \(error)")

            case .pipelineStarted:
                logger.info("Pipeline started")

            case .pipelineCompleted:
                logger.info("Pipeline completed")

            default:
                break
            }
        }
    }

    // MARK: - Legacy Compatibility Methods

    func startRecording() async throws {
        await startConversation()
    }

    func stopRecordingAndProcess() async throws -> VoicePipelineResult {
        await stopConversation()

        // Return a mock result for compatibility
        return VoicePipelineResult(
            transcription: STTResult(
                text: currentTranscript,
                language: "en",
                confidence: 0.95,
                duration: 0
            ),
            llmResponse: assistantResponse,
            audioOutput: nil,
            processingTime: 0,
            stageTiming: [:]
        )
    }

    func speakResponse(_ text: String) async {
        logger.info("Speaking response: '\(text, privacy: .public)'")
        // TTS is now handled by the pipeline
    }
}

// MARK: - VoicePipelineManagerDelegate

// Delegate no longer needed - ModularVoicePipeline uses events
/*
extension VoiceAssistantViewModel: @preconcurrency ModularPipelineDelegate {
    nonisolated func pipeline(_ pipeline: ModularVoicePipeline, didReceiveEvent event: ModularPipelineEvent) {
        Task { @MainActor in
            await handlePipelineEvent(event)
        }
    }

    nonisolated func pipeline(_ pipeline: ModularVoicePipeline, didEncounterError error: Error) {
        Task { @MainActor in

            errorMessage = error.localizedDescription
            sessionState = .error(error.localizedDescription)
            isListening = false
            isProcessing = false
            logger.error("Pipeline error: \(error)")
        }
    }K
}
*/
