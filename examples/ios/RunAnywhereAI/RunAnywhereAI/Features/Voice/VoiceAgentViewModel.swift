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
            return "Tap to send · Hold to stop"
        case .processing:
            return "Processing your message..."
        case .speaking:
            return "Speaking..."
        case .connecting:
            return "Connecting..."
        case .connected:
            return "Tap to speak · Hold to end"
        default:
            return "Tap to start conversation"
        }
    }

    // MARK: - Private State

    // v3.1: migrated off the deprecated VoiceSessionHandle to
    // `RunAnywhere.streamVoiceAgent()` — the public proto-stream surface.
    // The SDK wraps the raw C handle internally; we just consume
    // `RAVoiceEvent`s and switch on `event.payload` in
    // `handleProtoEvent(_:)` below.
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

        logger.info("Model states synced - VAD: \(states.vad.isLoaded), STT: \(states.stt.isLoaded), LLM: \(states.llm.isLoaded), TTS: \(states.tts.isLoaded)")
    }

    private func mapState(_ state: ComponentLoadState) -> ModelLoadState {
        switch state {
        case .unspecified, .notLoaded: return .notLoaded
        case .loading: return .loading
        case .loaded: return .loaded
        case .error: return .error("Component failed")
        case .UNRECOGNIZED(_): return .error("Unknown component state")
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
        // Events now come from C++ via generic BridgedEvent
        // Handle by event type string and category
        switch event.category {
        case .llm:
            handleLLMEvent(event)
        case .stt:
            handleSTTEvent(event)
        case .tts:
            handleTTSEvent(event)
        default:
            break
        }
    }

    private func handleLLMEvent(_ event: any SDKEvent) {
        let modelId = event.properties["model_id"] ?? ""
        let errorMessage = event.properties["error_message"]

        switch event.type {
        case "llm_model_load_started":
            llmModelState = .loading
        case "llm_model_load_completed":
            llmModelState = .loaded
            updateModel(.llm, id: modelId)
        case "llm_model_load_failed":
            llmModelState = .error(errorMessage ?? "Unknown error")
        case "llm_model_unloaded":
            llmModelState = .notLoaded
            llmModel = nil
        default:
            break
        }
    }

    private func handleSTTEvent(_ event: any SDKEvent) {
        let modelId = event.properties["model_id"] ?? ""
        let errorMessage = event.properties["error_message"]

        switch event.type {
        case "stt_model_load_started":
            sttModelState = .loading
        case "stt_model_load_completed":
            sttModelState = .loaded
            updateModel(.stt, id: modelId)
        case "stt_model_load_failed":
            sttModelState = .error(errorMessage ?? "Unknown error")
        case "stt_model_unloaded":
            sttModelState = .notLoaded
            sttModel = nil
        default:
            break
        }
    }

    private func handleTTSEvent(_ event: any SDKEvent) {
        let modelId = event.properties["model_id"] ?? ""
        let errorMessage = event.properties["error_message"]

        switch event.type {
        case "tts_voice_load_started":
            ttsModelState = .loading
        case "tts_voice_load_completed":
            ttsModelState = .loaded
            updateModel(.tts, id: modelId)
        case "tts_voice_load_failed":
            ttsModelState = .error(errorMessage ?? "Unknown error")
        case "tts_voice_unloaded":
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

    /// Start a voice conversation using the canonical
    /// `RunAnywhere.streamVoiceAgent()` proto-stream API.
    ///
    /// Pipeline:
    ///   1. Initialize voice agent against already-loaded STT/LLM/TTS models.
    ///   2. Consume `AsyncStream<RAVoiceEvent>` from `streamVoiceAgent()`.
    ///   3. Drive UI state by switching on `event.payload` in
    ///      `handleProtoEvent(_:)`.
    ///
    /// `RunAnywhere.startVoiceSession` and `VoiceSessionHandle` were
    /// removed in the v2 close-out; the SDK now exposes the proto stream
    /// directly so example apps no longer reach into `CppBridge` /
    /// `CRACommons`.
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

        // Clear previous conversation when starting a new one
        currentTranscript = ""
        assistantResponse = ""

        do {
            // Initialize voice agent against the currently-loaded models.
            // SettingsViewModel's continuousMode/thinking/maxTokens land at the C
            // layer via a future config surface; v3.1 keeps the init minimal.
            try await RunAnywhere.initializeVoiceAgentWithLoadedModels()

            sessionState = .listening
            currentStatus = "Listening..."

            // Consume the public proto-event stream. The SDK constructs the
            // adapter internally and tears it down via `onTermination` when
            // the consuming task is cancelled.
            eventTask = Task { [weak self] in
                for await event in RunAnywhere.streamVoiceAgent() {
                    await MainActor.run { self?.handleProtoEvent(event) }
                }
            }

            logger.info("Voice session started successfully (RunAnywhere.streamVoiceAgent)")
        } catch {
            sessionState = .error(error.localizedDescription)
            currentStatus = "Error"
            errorMessage = "Failed to start session: \(error.localizedDescription)"
            logger.error("Failed to start voice session: \(error.localizedDescription)")
        }
    }

    /// Stop the current voice conversation.
    func stopConversation() async {
        logger.info("Stopping voice session...")
        eventTask?.cancel()
        eventTask = nil
        sessionState = .disconnected
        currentStatus = "Ready"
        audioLevel = 0.0
        isSpeechDetected = false
        logger.info("Voice session stopped")
    }

    /// Interrupt currently-playing speech. v3.1: handled at the C layer via
    /// the voice agent's interrupted event. UI only needs to reset state;
    /// actual audio-pipeline interruption is driven by the C++ agent when
    /// VAD detects new speech or the user taps stop.
    func interruptSpeaking() async {
        // No-op at the Swift layer — the C voice agent owns barge-in.
        // Future: expose rac_voice_agent_interrupt(handle) if needed.
        logger.debug("interruptSpeaking: C-layer handled")
    }

    /// Push-to-talk: force-send the current audio buffer.
    func sendAudioNow() async {
        // No-op at the Swift layer — the C voice agent's VAD triggers on
        // end-of-utterance. Future: expose rac_voice_agent_force_commit(handle).
        logger.debug("sendAudioNow: C-layer handled (relies on VAD end-of-utterance)")
    }

    /// Resume listening after a turn.
    func resumeListening() async {
        // No-op at the Swift layer — the C voice agent loops back to
        // listening automatically when continuousMode is set. For
        // push-to-talk, calling startConversation() again re-initializes.
        logger.debug("resumeListening: C-layer handled")
    }

    // MARK: - Proto Event Handling (v3.1)

    /// Drive UI state from the canonical `RAVoiceEvent` proto.
    ///
    /// The old `handleSessionEvent(VoiceSessionEvent)` mapped 10 UX cases to
    /// UI state. This version switches on the proto oneof `event.payload`
    /// directly.
    private func handleProtoEvent(_ event: RAVoiceEvent) {
        switch event.payload {
        case let .state(state):
            switch state.current {
            case .idle:
                sessionState = .listening
                currentStatus = "Listening..."
            case .listening:
                if sessionState != .listening && sessionState != .speaking && sessionState != .processing {
                    sessionState = .listening
                    currentStatus = "Listening..."
                }
            case .thinking:
                sessionState = .processing
                currentStatus = "Processing..."
                isSpeechDetected = false
            case .speaking:
                sessionState = .speaking
                currentStatus = "Speaking..."
            case .stopped:
                sessionState = .disconnected
                currentStatus = "Ready"
            default:
                break
            }

        case let .vad(vad):
            switch vad.type {
            case .vadEventVoiceStart:
                isSpeechDetected = true
                currentStatus = "Listening..."
            case .vadEventVoiceEndOfUtterance:
                sessionState = .processing
                currentStatus = "Processing..."
                isSpeechDetected = false
            default:
                break
            }

        case let .userSaid(userSaid):
            currentTranscript = userSaid.text

        case let .assistantToken(token):
            // Append incrementally; proto emits per-token streaming.
            assistantResponse += token.text

        case .audio:
            sessionState = .speaking
            currentStatus = "Speaking..."

        case let .error(err):
            logger.error("Voice agent error: \(err.message)")
            errorMessage = err.message

        case .wakewordDetected:
            sessionState = .listening
            currentStatus = "Listening..."
            isSpeechDetected = false

        case .interrupted, .metrics, .none:
            // No UX-visible effect for these arms today.
            break

        // Phase B regenerated RAVoiceEvent payload with new arms; we do not
        // surface them in the UI yet, so they are intentionally folded into
        // the same no-op bucket as .interrupted / .metrics.
        case .componentStateChanged, .sessionError, .sessionStarted,
             .sessionStopped, .agentResponseStarted, .agentResponseCompleted,
             .speechTurnDetection, .turnLifecycle:
            break
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

    var currentSTTModel: String {
        sttModel?.name.modelNameFromID() ?? "Not loaded"
    }
    var currentLLMModel: String {
        llmModel?.name.modelNameFromID() ?? "Not loaded"
    }
    var currentTTSModel: String {
        ttsModel?.name.modelNameFromID() ?? "Not loaded"
    }
    var whisperModel: String { currentSTTModel }
}
