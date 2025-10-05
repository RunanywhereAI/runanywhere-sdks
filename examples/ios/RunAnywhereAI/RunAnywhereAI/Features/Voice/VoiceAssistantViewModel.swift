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
    private let whisperModelName: String = "whisper-base"

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

        // Get current LLM model info
        updateModelInfo()

        // Set the Whisper model display name
        updateWhisperModelName()

        // Listen for model changes
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

    private func updateWhisperModelName() {
        switch whisperModelName {
        case "whisper-base":
            whisperModel = "Whisper Base"
        case "whisper-small":
            whisperModel = "Whisper Small"
        case "whisper-medium":
            whisperModel = "Whisper Medium"
        case "whisper-large":
            whisperModel = "Whisper Large"
        case "whisper-large-v3":
            whisperModel = "Whisper Large v3"
        default:
            whisperModel = whisperModelName.replacingOccurrences(of: "-", with: " ").capitalized
        }
        logger.info("Using Whisper model: \(self.whisperModel)")
    }

    // MARK: - Conversation Control

    /// Start real-time conversation using modular pipeline
    func startConversation() async {
        logger.info("Starting conversation with modular pipeline...")

        sessionState = .connecting
        currentStatus = "Initializing components..."

        // Create pipeline configuration with balanced VAD threshold
        // Always include LLM component for complete pipeline flow
        let config = ModularPipelineConfig(
            components: [.vad, .stt, .llm, .tts],
            vad: VADConfig(energyThreshold: 0.006), // Optimized threshold for normal speaking voice
            stt: VoiceSTTConfig(modelId: whisperModelName),
            llm: VoiceLLMConfig(
                modelId: "default",
                systemPrompt: "You are a helpful voice assistant. Keep responses concise and conversational.",
                maxTokens: 100  // Limit response to 100 tokens for concise voice interactions
            ),
            // llm: VoiceLLMConfig(modelId: "default", systemPrompt: "INSTRUCTION: Give a direct answer. Do not write dialogue. Do not write User: or Assistant:. Just answer."),
            tts: VoiceTTSConfig(voice: "system")
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
            case .vadSpeechStart:
                sessionState = .listening
                currentStatus = "Listening..."
                isSpeechDetected = true
                logger.info("Speech detected")

            case .vadSpeechEnd:
                isSpeechDetected = false
                logger.info("Speech ended")

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
