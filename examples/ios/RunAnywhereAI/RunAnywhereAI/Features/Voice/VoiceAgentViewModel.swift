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

// swiftlint:disable type_body_length

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

    // Voice uses `RunAnywhere.streamVoiceAgent()`, the public proto-stream
    // surface. The SDK wraps the raw C handle internally; this view model
    // consumes `RAVoiceEvent`s and switches on `event.payload`.
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

    /// Sync model states from SDK via canonical component lifecycle snapshot API.
    private func syncModelStates() async {
        let sttState = componentStateFromSnapshot(.stt)
        let llmState = componentStateFromSnapshot(.llm)
        let ttsState = componentStateFromSnapshot(.tts)
        let vadState = componentStateFromSnapshot(.vad)

        sttModelState = mapState(sttState)
        llmModelState = mapState(llmState)
        ttsModelState = mapState(ttsState)

        // swiftlint:disable:next line_length
        logger.info("Model states synced - VAD: \(vadState.isLoaded), STT: \(sttState.isLoaded), LLM: \(llmState.isLoaded), TTS: \(ttsState.isLoaded)")
    }

    // RAComponentLoadState consolidated into the richer
    // RAComponentLifecycleState (shared with SDKEvent).
    private func componentStateFromSnapshot(_ component: RASDKComponent) -> RAComponentLifecycleState {
        guard let snapshot = RunAnywhere.componentLifecycleSnapshot(component) else {
            return .notLoaded
        }
        return snapshot.state
    }

    private func mapState(_ state: RAComponentLifecycleState) -> ModelLoadState {
        switch state {
        case .unspecified, .notLoaded: return .notLoaded
        case .loading, .downloading, .updating: return .loading
        case .ready: return .loaded
        case .error: return .error("Component failed")
        case .unloading, .shutdown, .deleting, .paused: return .notLoaded
        case .UNRECOGNIZED: return .error("Unknown component state")
        }
    }

    private enum ModelType {
        case stt, llm, tts

        var category: ModelCategory {
            switch self {
            case .stt: return .speechRecognition
            case .llm: return .language
            case .tts: return .speechSynthesis
            }
        }
    }

    private func updateModel(_ type: ModelType, id: String) {
        // Find model info from shared model list
        let model = ModelListViewModel.shared.availableModels.first { $0.id == id }
        let name = model?.name ?? id
        let framework = model?.framework ?? type.category.defaultFramework
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

        let bus = RunAnywhere.events

        bus.events(for: .component)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in Task { @MainActor in self?.handleComponentLifecycleEvent(event) } }
            .store(in: &cancellables)

        bus.events(for: .llm)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in Task { @MainActor in self?.handleLLMEvent(event) } }
            .store(in: &cancellables)

        bus.events(for: .stt)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in Task { @MainActor in self?.handleSTTEvent(event) } }
            .store(in: &cancellables)

        bus.events(for: .tts)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in Task { @MainActor in self?.handleTTSEvent(event) } }
            .store(in: &cancellables)
    }

    /// Handle the canonical component-lifecycle proto event published by
    /// `rac_model_lifecycle_load_proto` / `..._unload_proto`. This is how the
    /// STT "Use" action (and every other modality that routes through
    /// `RunAnywhere.loadModel`) signals load/unload completion to the app.
    private func handleComponentLifecycleEvent(_ event: RASDKEvent) {
        let lifecycle = event.componentLifecycle
        let modelId = lifecycle.modelID
        let state = mapState(lifecycle.currentState)

        switch lifecycle.component {
        case .llm:
            llmModelState = state
            if case .loaded = state, !modelId.isEmpty {
                updateModel(.llm, id: modelId)
            } else if case .notLoaded = state {
                llmModel = nil
            }
        case .stt:
            sttModelState = state
            if case .loaded = state, !modelId.isEmpty {
                updateModel(.stt, id: modelId)
            } else if case .notLoaded = state {
                sttModel = nil
            }
        case .tts:
            ttsModelState = state
            if case .loaded = state, !modelId.isEmpty {
                updateModel(.tts, id: modelId)
            } else if case .notLoaded = state {
                ttsModel = nil
            }
        default:
            break
        }
    }

    private func handleLLMEvent(_ event: RASDKEvent) {
        let modelId = event.model.modelID.isEmpty ? event.generation.modelID : event.model.modelID
        let errorMessage = event.model.error.isEmpty ? event.generation.error : event.model.error

        switch (event.model.kind, event.generation.kind) {
        case (.loadStarted, _):
            llmModelState = .loading
        case (.loadCompleted, _), (_, .modelLoaded):
            llmModelState = .loaded
            updateModel(.llm, id: modelId)
        case (.loadFailed, _), (_, .failed):
            llmModelState = .error(errorMessage.isEmpty ? "Unknown error" : errorMessage)
        case (.unloadCompleted, _), (_, .modelUnloaded):
            llmModelState = .notLoaded
            llmModel = nil
        default:
            break
        }
    }

    private func handleSTTEvent(_ event: RASDKEvent) {
        let modelId = event.model.modelID
        let errorMessage = event.model.error

        switch event.model.kind {
        case .loadStarted:
            sttModelState = .loading
        case .loadCompleted:
            sttModelState = .loaded
            updateModel(.stt, id: modelId)
        case .loadFailed:
            sttModelState = .error(errorMessage.isEmpty ? "Unknown error" : errorMessage)
        case .unloadCompleted:
            sttModelState = .notLoaded
            sttModel = nil
        default:
            break
        }
    }

    private func handleTTSEvent(_ event: RASDKEvent) {
        let modelId = event.model.modelID
        let errorMessage = event.model.error

        switch event.model.kind {
        case .loadStarted:
            ttsModelState = .loading
        case .loadCompleted:
            ttsModelState = .loaded
            updateModel(.tts, id: modelId)
        case .loadFailed:
            ttsModelState = .error(errorMessage.isEmpty ? "Unknown error" : errorMessage)
        case .unloadCompleted:
            ttsModelState = .notLoaded
            ttsModel = nil
        default:
            break
        }
    }

    // MARK: - Model Selection

    /// Commit the selected STT model to the Voice Agent pipeline.
    ///
    /// Called from the "Use" action in the STT picker after
    /// `RunAnywhere.loadModel` has already loaded the model into the C++
    /// lifecycle for `SDK_COMPONENT_STT`. This updates the Voice tab's
    /// pipeline slot and re-syncs `sttModelState` from the canonical
    /// component snapshot so the setup card transitions to "Loaded".
    func setSTTModel(_ model: RAModelInfo) async {
        sttModel = SelectedModelInfo(framework: model.framework, name: model.name, id: model.id)
        sttModelState = .loaded  // Optimistic — corrected by snapshot below.
        await syncModelStates()
    }

    /// Commit the selected LLM model to the Voice Agent pipeline.
    func setLLMModel(_ model: RAModelInfo) async {
        llmModel = SelectedModelInfo(framework: model.framework, name: model.name, id: model.id)
        llmModelState = .loaded
        await syncModelStates()
    }

    /// Commit the selected TTS model to the Voice Agent pipeline.
    func setTTSModel(_ model: RAModelInfo) async {
        ttsModel = SelectedModelInfo(framework: model.framework, name: model.name, id: model.id)
        ttsModelState = .loaded
        await syncModelStates()
    }

    // MARK: - Conversation Control

    /// Start a voice conversation using the canonical
    /// `RunAnywhere.streamVoiceAgent()` proto-stream API.
    ///
    /// The SDK owns the multi-step bootstrap (VAD auto-load + model
    /// composition + initialization) via
    /// `initializeVoiceAgentWithLoadedModels()`; this view-model only
    /// drives UI state and consumes the resulting proto stream.
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
        currentTranscript = ""
        assistantResponse = ""

        do {
            try await RunAnywhere.initializeVoiceAgentWithLoadedModels()

            sessionState = .listening
            currentStatus = "Listening..."

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
    ///
    /// Mirrors Android `VoiceViewModel.stop()`: cancel the event stream and
    /// reset UI state first, then release the SDK's voice-agent resources.
    /// `cleanupVoiceAgent()` never throws and is safe to call anytime.
    func stopConversation() async {
        logger.info("Stopping voice session...")
        eventTask?.cancel()
        eventTask = nil
        sessionState = .disconnected
        currentStatus = "Ready"
        audioLevel = 0.0
        isSpeechDetected = false
        await RunAnywhere.cleanupVoiceAgent()
        logger.info("Voice session stopped")
    }

    // MARK: - Proto Event Handling

    // swiftlint:disable cyclomatic_complexity function_body_length

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
            case .speechActivity:
                if vad.isSpeech {
                    isSpeechDetected = true
                    currentStatus = "Listening..."
                } else {
                    sessionState = .processing
                    currentStatus = "Processing..."
                    isSpeechDetected = false
                }
            case .stopped:
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
            sessionState = .error(err.message)
            currentStatus = "Error"

        case let .sessionError(err):
            logger.error("Voice session error: \(err.message)")
            errorMessage = err.message
            if !err.recoverable {
                sessionState = .error(err.message)
                currentStatus = "Error"
            }

        case .sessionStopped:
            sessionState = .disconnected
            currentStatus = "Ready"
            audioLevel = 0
            isSpeechDetected = false

        case .sessionStarted:
            sessionState = .listening
            currentStatus = "Listening..."

        case .agentResponseStarted:
            assistantResponse = ""
            currentTranscript = ""

        case .agentResponseCompleted:
            sessionState = .listening
            currentStatus = "Listening..."

        case let .audioLevel(level):
            audioLevel = min(max(level.rms, 0), 1)

        case .wakewordDetected:
            sessionState = .listening
            currentStatus = "Listening..."
            isSpeechDetected = false

        case .interrupted, .metrics, .none:
            break

        case .componentStateChanged, .speechTurnDetection, .turnLifecycle:
            break
        default:
            break
        }
    }

    // swiftlint:enable cyclomatic_complexity function_body_length

    // MARK: - Cleanup

    func cleanup() {
        eventTask?.cancel()
        eventTask = nil
        cancellables.removeAll()
        isViewModelInitialized = false
        hasSubscribedToSDKEvents = false
        // VM teardown path (view's onDisappear) — Android's lifecycle
        // equivalent (`onCleared()` → `stop()`) also releases the agent here.
        Task {
            await RunAnywhere.cleanupVoiceAgent()
        }
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
// swiftlint:enable type_body_length
