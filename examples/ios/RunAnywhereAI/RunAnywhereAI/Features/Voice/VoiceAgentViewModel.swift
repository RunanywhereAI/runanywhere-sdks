//
//  VoiceAgentViewModel.swift
//  RunAnywhereAI
//
//  A clean, refactored ViewModel for Voice Assistant functionality.
//  Orchestrates the complete STT → LLM → TTS pipeline with proper state management.
//
//  MVVM Principles:
//  - ALL business logic lives in this ViewModel
//  - Views only observe state and call ViewModel methods
//  - No SDK calls or business logic in views
//

import Foundation
import SwiftUI
import RunAnywhere
import Combine
import os

/// A clean ViewModel for voice assistant using SDK's VoiceSession API.
///
/// This ViewModel orchestrates the complete voice AI pipeline:
/// - Audio capture and VAD (Voice Activity Detection)
/// - Speech-to-Text (STT) transcription
/// - Large Language Model (LLM) response generation
/// - Text-to-Speech (TTS) synthesis
/// - Audio playback coordination
///
/// The SDK handles the actual orchestration; this ViewModel bridges SDK events to UI state.
@MainActor
final class VoiceAgentViewModel: ObservableObject {
    // MARK: - Dependencies

    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "VoiceAgent")
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Published State (Observable by Views)

    /// Current session state
    @Published private(set) var sessionState: VoiceSessionState = .disconnected

    /// Initialization state
    @Published private(set) var isInitialized = false

    /// Audio level (0.0 to 1.0) for visual feedback
    @Published private(set) var audioLevel: Float = 0.0

    /// Current status message
    @Published private(set) var currentStatus = "Initializing..."

    /// Error message to display to user
    @Published private(set) var errorMessage: String?

    /// Current transcript from STT
    @Published private(set) var currentTranscript = ""

    /// Assistant's response from LLM
    @Published private(set) var assistantResponse = ""

    /// Whether speech is currently detected (for pulsing animation)
    @Published private(set) var isSpeechDetected = false

    // MARK: - Model Selection State

    /// Selected STT model
    @Published var sttModel: SelectedModelInfo?

    /// Selected LLM model
    @Published var llmModel: SelectedModelInfo?

    /// Selected TTS model
    @Published var ttsModel: SelectedModelInfo?

    /// STT model loading state
    @Published private(set) var sttModelState: ModelLoadState = .notLoaded

    /// LLM model loading state
    @Published private(set) var llmModelState: ModelLoadState = .notLoaded

    /// TTS model loading state
    @Published private(set) var ttsModelState: ModelLoadState = .notLoaded

    // MARK: - Computed Properties (for View)

    /// Whether all required models are loaded
    var allModelsLoaded: Bool {
        sttModelState.isLoaded && llmModelState.isLoaded && ttsModelState.isLoaded
    }

    /// Whether currently listening
    var isListening: Bool {
        sessionState == .listening
    }

    /// Whether currently processing
    var isProcessing: Bool {
        sessionState == .processing
    }

    /// Whether currently speaking
    var isSpeaking: Bool {
        sessionState == .speaking
    }

    /// Whether the session is active (any state except disconnected/connected)
    var isActive: Bool {
        switch sessionState {
        case .listening, .processing, .speaking, .connecting:
            return true
        default:
            return false
        }
    }

    /// Status color for UI indicators
    var statusColor: StatusColor {
        switch sessionState {
        case .disconnected: return .gray
        case .connecting: return .orange
        case .connected: return .green
        case .listening: return .red
        case .processing: return .orange
        case .speaking: return .green
        case .error: return .red
        }
    }

    /// Microphone button color
    var micButtonColor: MicButtonColor {
        switch sessionState {
        case .connecting: return .orange
        case .listening: return .red
        case .processing: return .orange
        case .speaking: return .green
        default: return .orange
        }
    }

    /// Microphone button icon
    var micButtonIcon: String {
        switch sessionState {
        case .listening: return "mic.fill"
        case .speaking: return "speaker.wave.2.fill"
        case .processing: return "waveform"
        default: return "mic"
        }
    }

    /// Instruction text for current state
    var instructionText: String {
        switch sessionState {
        case .listening:
            return "Listening... Pause to send"
        case .processing:
            return "Processing your message..."
        case .speaking:
            return "Speaking..."
        case .connecting:
            return "Connecting..."
        default:
            return "Tap to start conversation"
        }
    }

    // MARK: - Private State

    private var session: VoiceSessionHandle?
    private var eventTask: Task<Void, Never>?

    // MARK: - Initialization State (for idempotency)

    private var isViewModelInitialized = false
    private var hasSubscribedToSDKEvents = false

    // MARK: - Initialization

    /// Initialize the ViewModel and subscribe to SDK events
    /// This method is idempotent - calling it multiple times is safe
    func initialize() async {
        guard !isViewModelInitialized else {
            logger.debug("Voice agent already initialized, skipping")
            return
        }
        isViewModelInitialized = true

        logger.info("Initializing voice agent...")

        // Subscribe to SDK component events for model state tracking
        subscribeToSDKEvents()

        // Sync current model states from SDK
        await syncModelStates()

        currentStatus = "Ready"
        isInitialized = true
        logger.info("Voice agent initialized successfully")
    }

    // MARK: - Model State Management

    /// Refresh component states from SDK (useful after model loading in another view)
    func refreshComponentStatesFromSDK() {
        Task {
            await syncModelStates()
        }
    }

    /// Sync model states from SDK
    private func syncModelStates() async {
        let states = await RunAnywhere.getVoiceAgentComponentStates()

        sttModelState = mapState(states.stt)
        llmModelState = mapState(states.llm)
        ttsModelState = mapState(states.tts)

        if case .loaded(let id) = states.stt { updateModel(.stt, id: id) }
        if case .loaded(let id) = states.llm { updateModel(.llm, id: id) }
        if case .loaded(let id) = states.tts { updateModel(.tts, id: id) }

        logger.info("Model states synced - STT: \(states.stt.isLoaded), LLM: \(states.llm.isLoaded), TTS: \(states.tts.isLoaded)")
    }

    private func mapState(_ state: ComponentLoadState) -> ModelLoadState {
        switch state {
        case .notLoaded: return .notLoaded
        case .loading: return .loading
        case .loaded: return .loaded
        case .error(let message): return .error(message)
        }
    }

    private enum ModelType { case stt, llm, tts }

    private func updateModel(_ type: ModelType, id: String) {
        // Find model info from shared model list
        let model = ModelListViewModel.shared.availableModels.first { $0.id == id }
        let name = model?.name ?? id
        let framework = model?.framework ?? (type == .llm ? .llamaCpp : .onnx)  // Fallback only if no model selected
        let selectedModel = SelectedModelInfo(framework: framework, name: name, id: id)

        switch type {
        case .stt:
            sttModel = selectedModel
        case .llm:
            llmModel = selectedModel
        case .tts:
            ttsModel = selectedModel
        }
    }

    // MARK: - SDK Event Subscription

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

    private func handleSDKEvent(_ event: any SDKEvent) {
        if let llmEvent = event as? LLMEvent {
            handleLLMEvent(llmEvent)
        } else if let sttEvent = event as? STTEvent {
            handleSTTEvent(sttEvent)
        } else if let ttsEvent = event as? TTSEvent {
            handleTTSEvent(ttsEvent)
        }
    }

    private func handleLLMEvent(_ event: LLMEvent) {
        switch event {
        case .modelLoadStarted:
            llmModelState = .loading
        case .modelLoadCompleted(let id, _, _, _):
            llmModelState = .loaded
            updateModel(.llm, id: id)
        case .modelLoadFailed(_, let error, _):
            llmModelState = .error(error.message)
        case .modelUnloaded:
            llmModelState = .notLoaded
            llmModel = nil
        default:
            break
        }
    }

    private func handleSTTEvent(_ event: STTEvent) {
        switch event {
        case .modelLoadStarted:
            sttModelState = .loading
        case .modelLoadCompleted(let id, _, _, _):
            sttModelState = .loaded
            updateModel(.stt, id: id)
        case .modelLoadFailed(_, let error, _):
            sttModelState = .error(error.message)
        case .modelUnloaded:
            sttModelState = .notLoaded
            sttModel = nil
        default:
            break
        }
    }

    private func handleTTSEvent(_ event: TTSEvent) {
        switch event {
        case .modelLoadStarted:
            ttsModelState = .loading
        case .modelLoadCompleted(let id, _, _, _):
            ttsModelState = .loaded
            updateModel(.tts, id: id)
        case .modelLoadFailed(_, let error, _):
            ttsModelState = .error(error.message)
        case .modelUnloaded:
            ttsModelState = .notLoaded
            ttsModel = nil
        default:
            break
        }
    }

    // MARK: - Model Selection

    /// Set the STT model
    func setSTTModel(_ model: ModelInfo) {
        sttModel = SelectedModelInfo(framework: model.framework, name: model.name, id: model.id)
        Task {
            await syncModelStates()
        }
    }

    /// Set the LLM model
    func setLLMModel(_ model: ModelInfo) {
        llmModel = SelectedModelInfo(framework: model.framework, name: model.name, id: model.id)
        Task {
            await syncModelStates()
        }
    }

    /// Set the TTS model
    func setTTSModel(_ model: ModelInfo) {
        ttsModel = SelectedModelInfo(framework: model.framework, name: model.name, id: model.id)
        Task { await syncModelStates() }
    }

    // MARK: - Conversation Control

    /// Start a voice conversation session
    func startConversation() async {
        guard allModelsLoaded else {
            sessionState = .error("Models not ready")
            errorMessage = "Please ensure all models (STT, LLM, TTS) are loaded before starting"
            logger.warning("Attempted to start conversation without all models loaded")
            return
        }

        sessionState = .connecting
        currentStatus = "Connecting..."
        errorMessage = nil

        do {
            session = try await RunAnywhere.startVoiceSession()
            sessionState = .listening
            currentStatus = "Listening..."
            eventTask = Task { [weak self] in
                guard let session = self?.session else { return }
                for await event in session.events {
                    await MainActor.run { self?.handleSessionEvent(event) }
                }
            }
            logger.info("Voice session started successfully")
        } catch {
            sessionState = .error(error.localizedDescription)
            currentStatus = "Error"
            errorMessage = "Failed to start session: \(error.localizedDescription)"
            logger.error("Failed to start voice session: \(error.localizedDescription)")
        }
    }

    /// Stop the current voice conversation
    func stopConversation() async {
        logger.info("Stopping voice session...")
        eventTask?.cancel()
        eventTask = nil
        await session?.stop()
        session = nil
        sessionState = .disconnected
        currentStatus = "Ready"
        audioLevel = 0.0
        isSpeechDetected = false
        logger.info("Voice session stopped")
    }

    /// Force send current audio buffer (for push-to-talk mode)
    func sendAudioNow() async {
        await session?.sendNow()
        logger.debug("Forced audio send")
    }

    // MARK: - Session Event Handling

    private func handleSessionEvent(_ event: VoiceSessionEvent) {
        switch event {
        case .started: sessionState = .listening; currentStatus = "Listening..."
        case .listening(let level): audioLevel = level
        case .speechStarted: isSpeechDetected = true; currentStatus = "Listening..."
        case .processing: sessionState = .processing; currentStatus = "Processing..."; isSpeechDetected = false
        case .transcribed(let text): currentTranscript = text
        case .responded(let text): assistantResponse = text
        case .speaking: sessionState = .speaking; currentStatus = "Speaking..."
        case let .turnCompleted(transcript, response, _):
            currentTranscript = transcript; assistantResponse = response
            sessionState = .listening; currentStatus = "Listening..."
        case .stopped: sessionState = .disconnected; currentStatus = "Ready"
        case .error(let message): logger.error("Session error: \(message)"); errorMessage = message
        }
    }

    // MARK: - Cleanup

    func cleanup() {
        eventTask?.cancel()
        eventTask = nil
        cancellables.removeAll()
        isViewModelInitialized = false
        hasSubscribedToSDKEvents = false
        logger.info("VoiceAgentViewModel cleanup completed")
    }

    // MARK: - Helper Properties

    var currentSTTModel: String { sttModel?.name ?? "Not loaded" }
    var currentLLMModel: String { llmModel?.name ?? "Not loaded" }
    var currentTTSModel: String { ttsModel?.name ?? "Not loaded" }
    var whisperModel: String { currentSTTModel }
}
