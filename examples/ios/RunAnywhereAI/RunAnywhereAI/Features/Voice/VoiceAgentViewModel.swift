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

    // Hardware-aware, pure recommendation helpers (example-app only).
    private let recommendationEngine = ModelRecommendationEngine()
    private let tierResolver = HardwareTierResolver()

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

    /// Selected VAD model (auto-loaded by the SDK; surfaced for the setup card).
    @Published var vadModel: SelectedModelInfo?

    /// STT model loading state
    @Published private(set) var sttModelState: ModelLoadState = .notLoaded

    /// LLM model loading state
    @Published private(set) var llmModelState: ModelLoadState = .notLoaded

    /// TTS model loading state
    @Published private(set) var ttsModelState: ModelLoadState = .notLoaded

    // MARK: - One-tap Pipeline Setup State

    /// True while `downloadAndLoadAll()` is sequencing the trio's downloads/loads.
    @Published private(set) var isSettingUpPipeline = false

    /// Per-component download progress (0...1) while the one-tap setup runs.
    @Published private(set) var sttDownloadProgress: Double = 0
    @Published private(set) var llmDownloadProgress: Double = 0
    @Published private(set) var ttsDownloadProgress: Double = 0

    /// Human-readable status for the current setup step (e.g. "Downloading voice…").
    @Published private(set) var pipelineSetupStatus: String?

    /// Whether the best-for-device trio has been pre-selected into the slots.
    @Published private(set) var didPreselectPipeline = false

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
    /// True while `stopConversation` is tearing down the SDK voice agent. Blocks a
    /// restart until cleanup completes so we never run two mic drivers at once.
    private var isStopping = false

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

        // Ensure the catalog is loaded, then pre-select the best-for-device trio
        // so the user doesn't have to pick anything by hand.
        await ModelListViewModel.shared.loadModelsFromRegistry()

        // If cleanup() ran while we were awaiting above (the user left the tab
        // mid-initialization), it reset the init flags and removed our
        // subscriptions. Bail instead of marking ourselves initialized with no
        // live subscription — otherwise the next onAppear would take the refresh
        // branch and the tab would be "deaf" again.
        guard isViewModelInitialized else {
            logger.debug("Voice agent initialization superseded by cleanup; aborting")
            return
        }

        preselectRecommendedPipeline()

        currentStatus = "Ready"
        isInitialized = true
        logger.info("Voice agent initialized successfully")
    }

    // MARK: - Model State Management

    /// Refresh component states from SDK (useful after model loading in another view)
    func refreshComponentStatesFromSDK() {
        Task {
            await syncModelStates()
            preselectRecommendedPipeline()
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

    // MARK: - One-tap Pipeline Setup

    /// Pre-select the best-for-device STT + LLM + TTS (+ VAD) into the pipeline
    /// slots. Only fills slots the user hasn't already loaded, so a manual pick
    /// is never clobbered. Pure recommendation → app state; no SDK loads here.
    func preselectRecommendedPipeline() {
        let models = ModelListViewModel.shared.availableModels
        guard !models.isEmpty else { return }

        let tier = tierResolver.resolve(from: DeviceInfoService.shared.deviceInfo)
        let pipeline = recommendationEngine.recommendVoicePipeline(
            tier: tier,
            appleFoundationAvailable: tierResolver.appleFoundationAvailable,
            from: models
        )

        if sttModel == nil, let stt = pipeline.stt { sttModel = selectedInfo(stt) }
        if llmModel == nil, let llm = pipeline.llm { llmModel = selectedInfo(llm) }
        if ttsModel == nil, let tts = pipeline.tts { ttsModel = selectedInfo(tts) }
        if vadModel == nil, let vad = pipeline.vad { vadModel = selectedInfo(vad) }

        didPreselectPipeline = true
        logger.info("Preselected voice pipeline (tier: \(tier.displayName, privacy: .public))")
    }

    /// Download (if needed) and load all three pipeline components in sequence,
    /// reporting per-component progress. VAD is downloaded when needed; the SDK
    /// auto-loads it during `startConversation()`.
    func downloadAndLoadAll() async {
        guard !isSettingUpPipeline else { return }
        isSettingUpPipeline = true
        errorMessage = nil
        defer {
            isSettingUpPipeline = false
            pipelineSetupStatus = nil
        }

        let models = ModelListViewModel.shared.availableModels
        func model(_ id: String?) -> RAModelInfo? {
            guard let id else { return nil }
            return models.first { $0.id == id }
        }

        // VAD first (no user-facing slot, but required by the pipeline).
        if let vad = model(vadModel?.id) {
            await ensureDownloaded(vad) { _ in }
        }

        if let stt = model(sttModel?.id) {
            pipelineSetupStatus = "Setting up speech recognition…"
            await setup(stt, category: .speechRecognition) { [weak self] value in
                self?.sttDownloadProgress = value
            }
        }
        if let llm = model(llmModel?.id) {
            pipelineSetupStatus = "Setting up the assistant…"
            await setup(llm, category: .language) { [weak self] value in
                self?.llmDownloadProgress = value
            }
        }
        if let tts = model(ttsModel?.id) {
            pipelineSetupStatus = "Setting up the voice…"
            await setup(tts, category: .speechSynthesis) { [weak self] value in
                self?.ttsDownloadProgress = value
            }
        }

        await syncModelStates()
    }

    // MARK: - Setup helpers

    private func selectedInfo(_ model: RAModelInfo) -> SelectedModelInfo {
        SelectedModelInfo(framework: model.framework, name: model.name, id: model.id)
    }

    /// Download a model if it isn't already local/built-in, reporting progress.
    private func ensureDownloaded(_ model: RAModelInfo, progress: @escaping (Double) -> Void) async {
        guard !model.isBuiltIn, model.localPathURL == nil else {
            progress(1)
            return
        }
        do {
            try await RunAnywhere.downloadModel(model) { update in
                await MainActor.run { progress(Double(update.overallProgress)) }
            }
            await MainActor.run { progress(1) }
        } catch {
            let reason = error.localizedDescription
            logger.error("Voice component download failed for \(model.id, privacy: .public): \(reason, privacy: .public)")
        }
    }

    /// Download (if needed) then load one component into its SDK lifecycle slot.
    /// Loading is by model id — the SDK resolves the freshly downloaded path.
    private func setup(
        _ model: RAModelInfo,
        category: RAModelCategory,
        progress: @escaping (Double) -> Void
    ) async {
        await ensureDownloaded(model, progress: progress)

        var request = RAModelLoadRequest()
        request.modelID = model.id
        request.category = category
        let result = await RunAnywhere.loadModel(request)
        if !result.success {
            errorMessage = result.errorMessage.isEmpty
                ? "Failed to set up \(model.name)."
                : result.errorMessage
        }
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

        // Reentrancy guard: ignore a start while a session is already active/
        // connecting, or while a stop is still tearing down. Otherwise a second
        // streamVoiceAgent() spins up a second mic driver → permanent hot mic.
        switch sessionState {
        case .disconnected, .error:
            break
        default:
            logger.warning("Ignoring startConversation: session already active")
            return
        }
        guard !isStopping else {
            logger.warning("Ignoring startConversation: stop still in progress")
            return
        }
        eventTask?.cancel()
        eventTask = nil

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
        guard !isStopping else { return }
        isStopping = true
        logger.info("Stopping voice session...")
        eventTask?.cancel()
        eventTask = nil
        sessionState = .disconnected
        currentStatus = "Ready"
        audioLevel = 0.0
        isSpeechDetected = false
        await RunAnywhere.cleanupVoiceAgent()
        isStopping = false
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
        // Reset ALL init/idempotency state together (matches
        // VoiceComponentViewModelBase.cleanupBase()). The View's onAppear gates
        // re-initialization on the @Published `isInitialized`; leaving it true
        // across a leave+return made onAppear take the lightweight refresh branch
        // instead of initialize(), so subscribeToSDKEvents() never re-ran and the
        // Voice tab went "deaf" to model load/unload events.
        isInitialized = false
        isViewModelInitialized = false
        hasSubscribedToSDKEvents = false
        // Return the conversation-facing UI to a clean idle state (mirrors
        // stopConversation) so leaving mid-session doesn't strand a stale
        // "Listening…" / transcript / response when the tab is re-entered.
        sessionState = .disconnected
        currentStatus = "Ready"
        audioLevel = 0.0
        isSpeechDetected = false
        currentTranscript = ""
        assistantResponse = ""
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
    var currentVADModel: String {
        vadModel?.name.modelNameFromID() ?? "Speech detector"
    }
    var whisperModel: String { currentSTTModel }
}
// swiftlint:enable type_body_length
