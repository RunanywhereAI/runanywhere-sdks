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

    /// The SDK's measurement when the microphone is being read but is delivering
    /// no usable signal, or `nil` when it is. Held apart from `errorMessage`
    /// because nothing has failed — the session is live and will hear the moment
    /// signal arrives — and because it has to change what the rest of the panel
    /// says. While it is set, the status pill and the instruction line must stop
    /// claiming to be listening: this screen was showing "Listening" and "Go
    /// ahead — I'm listening" directly above the SDK's own "I can't hear you",
    /// which is the panel contradicting itself in the one situation where the
    /// user needs to be told to go and fix something.
    @Published private(set) var inputSilentDetail: String?

    /// Current transcript from STT
    @Published private(set) var currentTranscript = ""

    /// Whether `currentTranscript` is settled or still a live hypothesis.
    ///
    /// A partial hypothesis is a guess the recognizer will revise — words change
    /// under the reader as more audio arrives. Drawing it identically to the
    /// final transcript makes the panel look like it is malfunctioning, so the
    /// view marks it. `VoiceEvent.userTranscribed` has always carried the flag;
    /// this screen used to throw it away.
    @Published private(set) var isTranscriptFinal = false

    /// Assistant's response from LLM
    @Published private(set) var assistantResponse = ""

    /// Whether speech is currently detected (for pulsing animation)
    @Published private(set) var isSpeechDetected = false

    /// True from the moment `interrupt()` is called until the agent leaves
    /// `speaking`. The control is held disabled for that whole window rather
    /// than staying live and inviting a second press that would queue behind the
    /// first.
    @Published private(set) var isInterrupting = false

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

    /// True when the user stopped the setup themselves. A cancelled setup is not
    /// a failure, so it gets its own state instead of borrowing the error one or
    /// silently reverting to the untouched card.
    @Published private(set) var didCancelSetup = false

    /// Whether the best-for-device trio has been pre-selected into the slots.
    @Published private(set) var didPreselectPipeline = false

    /// The in-flight one-tap setup, held so Cancel has something to cancel.
    private var setupTask: Task<Void, Never>?

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

    /// What the status indicator says.
    ///
    /// `VoiceSessionState.displayName` maps both idle states to "Ready", which
    /// is a claim about the pipeline, not the session — and the same screen
    /// shows a setup card reading "Not set up" directly beneath it whenever the
    /// trio is missing. Two opposite statements about one thing. Idle-and-
    /// unequipped is "Needs setup"; idle-and-equipped is "Ready".
    var statusLabel: String {
        // A session that cannot hear anything is not "Listening", whatever the
        // pipeline state says.
        if inputSilentDetail != nil, isListening {
            return "No input"
        }
        switch sessionState {
        case .disconnected, .connected:
            return allModelsLoaded ? "Ready" : "Needs setup"
        default:
            return sessionState.displayName
        }
    }

    /// Status color for UI indicators
    var statusColor: StatusColor {
        switch sessionState {
        case .disconnected: return .gray
        case .connecting: return .orange
        // Green only once the pipeline can actually start; grey while it can't.
        case .connected: return allModelsLoaded ? .green : .gray
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

    /// Microphone button icon.
    ///
    /// While the agent is speaking the button's job is barge-in, so it carries
    /// `stop.fill` — the same glyph Stop Generating uses in the chat, meaning
    /// the same thing: end what is running. A speaker glyph there described the
    /// *state* and named no action, which is why nobody found the interrupt.
    var micButtonIcon: String {
        switch sessionState {
        case .listening: return "mic.fill"
        case .speaking: return "stop.fill"
        case .processing: return "waveform"
        default: return "mic"
        }
    }

    /// Whether the agent can be cut off right now.
    var canInterrupt: Bool {
        sessionState == .speaking && !isInterrupting
    }

    /// The verb for pressing a control on this platform.
    ///
    /// The Mac build was showing "Click the microphone to start" and "Tap to
    /// start conversation" about the same button on the same screen. One verb
    /// per platform, resolved in one place, so a screen cannot disagree with
    /// itself and iOS and macOS cannot drift apart.
    static let pressVerb: String = {
        #if os(macOS)
        return "Click"
        #else
        return "Tap"
        #endif
    }()

    /// What the primary control does in the current state.
    ///
    /// This used to promise "Tap to send" while listening and "Tap to speak"
    /// while connected, neither of which the button did — a tap is ignored in
    /// every state except idle. A control that names an action it will not
    /// perform is worse than an unlabelled one, so the copy now describes only
    /// what is actually wired: start when idle, and interrupt while the agent is
    /// talking.
    ///
    /// It no longer says "hold to end" either. Ending was reachable only through
    /// an invisible long press on the mic, and two measured 1.2 s / 1.5 s holds
    /// changed nothing — a gesture with no affordance, sitting under an
    /// interactive-glass layer that has already had to be worked around for
    /// taps. Ending is a visible `End` button now (`endButton` in
    /// `VoiceAssistantView`), so this line no longer has to teach a gesture.
    var instructionText: String {
        if inputSilentDetail != nil, sessionState == .listening {
            return "Check the microphone — nothing is reaching it"
        }
        switch sessionState {
        case .listening:
            return isSpeechDetected ? "Listening…" : "Go ahead — I'm listening"
        case .processing:
            return "Working out a reply…"
        case .speaking:
            // "Take the turn back" is the phrase all four apps use for this
            // moment, and it names the thing that always works.
            //
            // The microphone is no longer gated during playout — the SDK keeps
            // feeding it and the core decides whether a voice arriving over the
            // reply is a real interruption or the mic hearing the loudspeaker
            // (voice_agent_feed_abi.cpp). But that decision needs the user's
            // voice to arrive meaningfully louder at the mic than the agent's own
            // playout does, which depends on the device's speaker-to-mic
            // coupling, so it is not something this label can promise. It
            // therefore still names only the control.
            return isInterrupting ? "Stopping…" : "\(Self.pressVerb) to take the turn back"
        case .connecting:
            return "Connecting…"
        case .connected:
            return "Ready when you are"
        case .error:
            return "\(Self.pressVerb) to try again"
        case .disconnected:
            return "\(Self.pressVerb) to start conversation"
        }
    }

    /// What the mic button does right now, for VoiceOver and for the tooltip on
    /// a pointer platform. The Mac's accessibility tree reported this control as
    /// a bare 88x88 `AXButton` with no title, description or value, so a
    /// VoiceOver user could not tell it from the four other unnamed buttons on
    /// the same screen.
    var micButtonAccessibilityLabel: String {
        switch sessionState {
        case .speaking: return isInterrupting ? "Stopping the reply" : "Take the turn back"
        case .listening, .processing, .connecting, .connected: return "Voice conversation in progress"
        case .disconnected: return "Start conversation"
        case .error: return "Retry starting the conversation"
        }
    }

    /// What an empty transcript pane says, given what the agent is doing.
    ///
    /// These were fixed strings, so an empty pane read "Listening…" while the
    /// agent was thinking and "waiting for you" while it was already talking —
    /// the panel contradicting the status pill directly above it. An empty state
    /// is still a claim about the system, and it has to be a true one.
    var transcriptPlaceholder: String {
        if inputSilentDetail != nil, sessionState == .listening {
            return "Nothing is reaching the microphone."
        }
        switch sessionState {
        case .connecting: return "Getting ready…"
        case .listening: return isSpeechDetected ? "Listening…" : "Go ahead — say something."
        case .processing: return "Working out a reply…"
        // Was "Talk over it any time to interrupt". The microphone IS live
        // through playout now, but whether a voice over the reply is recognised
        // as an interruption depends on the device's speaker-to-mic coupling
        // (see `instructionText`), so this pane does not promise it. It states
        // the state, matching Android; the instruction line beside it names the
        // control that always works.
        case .speaking: return "Speaking."
        case .connected: return "Ready when you are."
        case .disconnected, .error: return "Nothing heard yet."
        }
    }

    var replyPlaceholder: String {
        switch sessionState {
        case .connecting: return "Getting ready…"
        case .listening: return "Waiting for you to finish speaking…"
        case .processing: return "Thinking…"
        case .speaking: return "Speaking…"
        case .connected: return "No reply yet."
        case .disconnected, .error: return "No reply yet."
        }
    }

    // MARK: - Private State

    // Voice runs on `RunAnywhere.voice.createSession(...)`. The session owns the
    // pipeline and the microphone; this view model only drives UI state from the
    // `VoiceEvent` stream.
    private var session: VoiceSession?
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

        let bus = RunAnywhere.eventBus

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
    /// `RunAnywhere.models.load`) signals load/unload completion to the app.
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

        // `GenerationEventKind.MODEL_LOADED`/`.MODEL_UNLOADED` were deleted
        // outright (idl/sdk_events.proto: "Model load/unload -> ModelEventKind")
        // -- `event.model.kind` is the sole load/unload signal now.
        switch (event.model.kind, event.generation.kind) {
        case (.loadStarted, _):
            llmModelState = .loading
        case (.loadCompleted, _):
            llmModelState = .loaded
            updateModel(.llm, id: modelId)
        case (.loadFailed, _), (_, .failed):
            llmModelState = .error(errorMessage.isEmpty ? "Unknown error" : errorMessage)
        case (.unloadCompleted, _):
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
    /// `RunAnywhere.models.load` has already loaded the model into the C++
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

    /// Start the one-tap setup, keeping the task so it can be cancelled.
    ///
    /// The view used to spawn this in an anonymous `Task`, so the only thing on
    /// screen while it ran was a spinner nobody could stop — and a first-run
    /// attempt that stalled left the user with no step, no percentage and no way
    /// out. Owning the task is what makes Cancel possible.
    func startPipelineSetup() {
        guard setupTask == nil else { return }
        setupTask = Task { [weak self] in
            await self?.downloadAndLoadAll()
            await MainActor.run { self?.setupTask = nil }
        }
    }

    /// Abandon the in-flight setup. Whatever already landed on disk stays there,
    /// so pressing "Set up Voice AI" again resumes rather than starts over.
    func cancelPipelineSetup() {
        guard let task = setupTask else { return }
        logger.info("Cancelling voice pipeline setup")
        setupTask = nil
        task.cancel()
        isSettingUpPipeline = false
        pipelineSetupStatus = nil
        didCancelSetup = true
    }

    /// Download (if needed) and load all three pipeline components in sequence,
    /// reporting per-component progress. VAD is downloaded when needed; the SDK
    /// auto-loads it during `startConversation()`.
    func downloadAndLoadAll() async {
        guard !isSettingUpPipeline else { return }
        isSettingUpPipeline = true
        errorMessage = nil
        didCancelSetup = false
        defer {
            isSettingUpPipeline = false
            pipelineSetupStatus = nil
        }

        let models = ModelListViewModel.shared.availableModels
        func model(_ id: String?) -> RAModelInfo? {
            guard let id else { return nil }
            return models.first { $0.id == id }
        }

        // VAD first (no user-facing slot, but required by the pipeline). The
        // status is set BEFORE the step, not after it: setting it afterwards
        // meant the whole first step — a download, on a fresh install — ran
        // behind a status of `nil`, i.e. a bare spinner that said nothing about
        // what was happening or whether it was stuck.
        if let vad = model(vadModel?.id) {
            pipelineSetupStatus = "Setting up speech detection…"
            await ensureDownloaded(vad) { _ in }
        }
        if Task.isCancelled { return }

        if let stt = model(sttModel?.id) {
            pipelineSetupStatus = "Setting up speech recognition…"
            await setup(stt) { [weak self] value in
                self?.sttDownloadProgress = value
            }
        }
        if Task.isCancelled { return }
        if let llm = model(llmModel?.id) {
            pipelineSetupStatus = "Setting up the assistant…"
            await setup(llm) { [weak self] value in
                self?.llmDownloadProgress = value
            }
        }
        if Task.isCancelled { return }
        if let tts = model(ttsModel?.id) {
            pipelineSetupStatus = "Setting up the voice…"
            await setup(tts) { [weak self] value in
                self?.ttsDownloadProgress = value
            }
        }

        await syncModelStates()
    }

    // MARK: - Setup helpers

    private func selectedInfo(_ model: RAModelInfo) -> SelectedModelInfo {
        SelectedModelInfo(framework: model.framework, name: model.name, id: model.id)
    }

    /// How a component download ended. `.cancelled` is the default rather than
    /// `.succeeded` on purpose: cancelling the consuming Task terminates the
    /// sequence without delivering the SDK's `.cancelled`, so defaulting to
    /// success would make a cancel look like a finished download.
    private enum DownloadOutcome {
        case succeeded
        case failed(String)
        case cancelled
    }

    /// Download a model if it isn't already local/built-in, reporting progress.
    ///
    /// Every case of `DownloadEvent` is folded, because
    /// `RunAnywhere.models.download(id:)` reports failure as a terminal
    /// `.failed` event and then finishes the sequence *normally* — it does not
    /// throw. The previous `if case .progress` filter therefore fell out of the
    /// bottom of the loop on failure, called `progress(1)`, and let `setup()`
    /// go on to load a model that was never on disk. The user saw a full
    /// progress bar and then a load error about the wrong thing.
    private func ensureDownloaded(
        _ model: RAModelInfo,
        progress: @escaping (Double) -> Void
    ) async -> DownloadOutcome {
        guard !model.isBuiltIn, model.localPathURL == nil else {
            progress(1)
            return .succeeded
        }
        var outcome: DownloadOutcome = .cancelled
        do {
            for try await event in try await RunAnywhere.models.download(id: model.id) {
                switch event {
                case .progress(let snapshot):
                    if let fraction = snapshot.fraction {
                        progress(Double(fraction))
                    }
                case .verifying, .extracting:
                    // Bytes have all arrived; what remains has no measurable
                    // position, so hold the bar full rather than implying more
                    // transfer is pending.
                    progress(1)
                case .completed:
                    progress(1)
                    outcome = .succeeded
                case .failed(_, _, let error):
                    outcome = .failed(error.localizedDescription)
                case .cancelled:
                    outcome = .cancelled
                case .started:
                    break
                }
            }
        } catch {
            outcome = .failed(error.localizedDescription)
        }
        if case .failed(let reason) = outcome {
            logger.error(
                "Voice component download failed for \(model.id, privacy: .public): \(reason, privacy: .public)"
            )
        }
        return outcome
    }

    /// Download (if needed) then load one component into its SDK lifecycle slot.
    /// Loading is by model id — the SDK resolves the freshly downloaded path.
    private func setup(
        _ model: RAModelInfo,
        progress: @escaping (Double) -> Void
    ) async {
        // Only load what actually arrived. Loading after a failed download
        // produces a second, misleading error about the load rather than
        // telling the user the download is what went wrong.
        switch await ensureDownloaded(model, progress: progress) {
        case .failed(let reason):
            errorMessage = "Couldn't download \(model.name): \(reason)"
            return
        case .cancelled:
            return
        case .succeeded:
            break
        }

        do {
            try await RunAnywhere.models.load(id: model.id)
        } catch {
            errorMessage = "Failed to set up \(model.name): \(error.localizedDescription)"
        }
    }

    // MARK: - Conversation Control

    /// Start a voice conversation through `RunAnywhere.voice.createSession(...)`.
    ///
    /// The session owns its prerequisites (VAD ensure, model loads, pipeline
    /// wiring) and opens the microphone only on `start()`; this view model just
    /// drives UI state from the event stream.
    // swiftlint:disable:next function_body_length
    func startConversation() async {
        guard allModelsLoaded,
              let sttId = sttModel?.id,
              let llmId = llmModel?.id,
              let ttsId = ttsModel?.id else {
            sessionState = .error("Models not ready")
            errorMessage = "Please ensure all models (STT, LLM, TTS) are loaded before starting"
            logger.warning("Attempted to start conversation without a loaded model trio")
            return
        }

        // Reentrancy guard: ignore a start while a session is already active/
        // connecting, or while a stop is still tearing down. Otherwise a second
        // session spins up a second mic driver → permanent hot mic.
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

        // Restarting from `.error` used to assign a fresh session straight over
        // the failed one, so the previous VoiceAgentMicDriver and its
        // AVAudioEngine kept capturing: two capture engines on one microphone,
        // and the Mac's menu-bar mic indicator lit while the panel said "Error".
        // Close whatever survived before building anything, exactly as
        // stopConversation does, so "try again" can never stack sessions.
        if let stale = session {
            session = nil
            await stale.close()
        }

        sessionState = .connecting
        currentStatus = "Connecting..."
        errorMessage = nil
        inputSilentDetail = nil
        currentTranscript = ""
        isTranscriptFinal = false
        assistantResponse = ""
        isSpeechDetected = false
        isInterrupting = false

        do {
            let session = try await RunAnywhere.voice.createSession(
                stt: ModelRef(id: sttId),
                llm: ModelRef(id: llmId),
                tts: ModelRef(id: ttsId)
            )
            self.session = session

            let events = session.events
            eventTask = Task { [weak self] in
                do {
                    for try await event in events {
                        await MainActor.run { self?.handleVoiceEvent(event) }
                    }
                } catch {
                    await MainActor.run { self?.handleSessionFailure(error) }
                }
            }

            try session.start()
            sessionState = .listening
            currentStatus = "Listening..."
            logger.info("Voice session started successfully")
        } catch {
            sessionState = .error(error.localizedDescription)
            currentStatus = "Error"
            errorMessage = "Failed to start session: \(error.localizedDescription)"
            logger.error("Failed to start voice session: \(error.localizedDescription)")
        }
    }

    /// Cut the agent off mid-utterance and hand the turn back.
    ///
    /// The single most-used control in a real voice conversation: a person who
    /// has heard enough talks over the assistant rather than hanging up. The SDK
    /// has always exposed `VoiceSession.interrupt()` and this screen never
    /// called it, so the only way to stop a long-winded reply was to end the
    /// session and release the microphone.
    ///
    /// `interrupt()` returns only once playback and any in-flight response have
    /// settled, so the control stays disabled for that whole window. The session
    /// stays open throughout — that is the difference between interrupting and
    /// hanging up.
    func interruptAgent() async {
        guard let session, !isInterrupting else { return }
        isInterrupting = true
        await session.interrupt()
        // Cleared here, unconditionally. It used to be cleared only by the agent
        // leaving `speaking`, which meant a single missed state event left
        // "Stopping…" on screen and `canInterrupt` false for the rest of the
        // session — the primary barge-in control dead until the user restarted.
        // `interrupt()` already awaits playout settlement, so by this line the
        // reply really has stopped; `apply(_:)` still clears the flag too, as
        // belt and braces for an interrupt that resolves out of order.
        isInterrupting = false
    }

    /// Stop the current voice conversation.
    ///
    /// Mirrors Android `VoiceViewModel.stop()`: cancel the event stream and
    /// reset UI state first, then close the session, which stops capture and
    /// releases the native pipeline.
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
        isInterrupting = false
        inputSilentDetail = nil
        let closing = session
        session = nil
        await closing?.close()
        isStopping = false
        logger.info("Voice session stopped")
    }

    // MARK: - Voice Event Handling

    /// Drive UI state from the session's `VoiceEvent` stream.
    private func handleVoiceEvent(_ event: VoiceEvent) {
        switch event {
        case .agentStateChanged(let state):
            apply(state)

        case .speechStarted:
            isSpeechDetected = true
            // A voice just arrived, so "I can't hear you" has stopped being true.
            // Leaving it up would have the panel telling the user it cannot hear
            // them while it transcribes them. Any recoverable note from the
            // previous turn is superseded for the same reason.
            inputSilentDetail = nil
            errorMessage = nil
            // Do NOT force `.listening` here. Speech starting while the agent is
            // talking is barge-in, not a state change — claiming "Listening"
            // over a reply that is still being spoken is the panel contradicting
            // itself. `agentStateChanged` is what moves the turn.
            if sessionState == .listening || sessionState == .connected {
                sessionState = .listening
                currentStatus = "Listening..."
            }

        case .speechEnded:
            isSpeechDetected = false

        case let .userTranscribed(text, isFinal):
            // A partial hypothesis overwrites the previous one; a final one ends
            // the user's turn, so the answer to the *previous* question stops
            // being the answer on screen.
            currentTranscript = text
            isTranscriptFinal = isFinal
            if isFinal { assistantResponse = "" }

        case .agentResponse(let text):
            // Emitted per token; append as it streams.
            assistantResponse += text

        case .inputSilent(let detail):
            // Not an error: the session is live and healthy, the microphone is
            // not delivering. Recorded as its own state so the status pill,
            // instruction line and transcript pane can all stop claiming to
            // listen while it holds.
            logger.warning("Voice input is silent: \(detail)")
            inputSilentDetail = detail

        case let .error(message, recoverable):
            logger.error("Voice session error: \(message)")
            errorMessage = message
            if !recoverable {
                sessionState = .error(message)
                currentStatus = "Error"
                isInterrupting = false
                isSpeechDetected = false
                releaseFailedSession()
            }
        }
    }

    /// Hand the microphone back after a fatal session error.
    ///
    /// `.error` used to be a pure UI state: the session object, its mic driver
    /// and that driver's AVAudioEngine all kept running behind a panel reading
    /// "Tap to try again", which is why the Mac's menu-bar recording indicator
    /// stayed lit for minutes after the pipeline had died. A dead pipeline must
    /// not hold a live microphone, so the session is released here and the next
    /// start builds a clean one.
    private func releaseFailedSession() {
        eventTask?.cancel()
        eventTask = nil
        audioLevel = 0.0
        guard let closing = session else { return }
        session = nil
        Task { await closing.close() }
    }

    private func apply(_ state: AgentState) {
        switch state {
        case .listening:
            sessionState = .listening
            currentStatus = "Listening..."
            isSpeechDetected = false
        case .thinking:
            // A new turn starts here: drop the previous answer. The user
            // transcript stays until the next `userTranscribed` replaces it.
            assistantResponse = ""
            sessionState = .processing
            currentStatus = "Processing..."
            isSpeechDetected = false
        case .speaking:
            sessionState = .speaking
            currentStatus = "Speaking..."
        }
        // Leaving `speaking` is what actually ends an interrupt, whether the
        // interrupt caused it or the agent simply finished the sentence.
        // `AgentState` is `Sendable` but not `Equatable`, hence the pattern
        // match rather than `state != .speaking`.
        if case .speaking = state {} else { isInterrupting = false }
    }

    /// The event stream threw, so the pipeline is no longer running.
    private func handleSessionFailure(_ error: Error) {
        guard !isStopping else { return }
        logger.error("Voice session stream failed: \(error.localizedDescription)")
        errorMessage = error.localizedDescription
        sessionState = .error(error.localizedDescription)
        currentStatus = "Error"
        isSpeechDetected = false
        isInterrupting = false
        releaseFailedSession()
    }

    // MARK: - Cleanup

    func cleanup() {
        eventTask?.cancel()
        eventTask = nil
        setupTask?.cancel()
        setupTask = nil
        isSettingUpPipeline = false
        pipelineSetupStatus = nil
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
        isInterrupting = false
        inputSilentDetail = nil
        currentTranscript = ""
        isTranscriptFinal = false
        assistantResponse = ""
        // VM teardown path (view's onDisappear) — Android's lifecycle
        // equivalent (`onCleared()` → `stop()`) also releases the agent here.
        let closing = session
        session = nil
        Task {
            await closing?.close()
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
