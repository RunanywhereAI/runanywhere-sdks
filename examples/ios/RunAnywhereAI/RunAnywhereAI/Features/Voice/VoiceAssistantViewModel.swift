import Foundation
import RunAnywhere
import Combine
import os

/// A simplified ViewModel for voice assistant using SDK's VoiceSession API.
///
/// The SDK handles all orchestration (audio capture, VAD, STT → LLM → TTS).
/// This ViewModel only bridges SDK events to UI state.
@MainActor
class VoiceAssistantViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "VoiceAssistant")
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Session State (for UI)
    enum SessionState: Equatable {
        case disconnected
        case connecting
        case connected
        case listening
        case processing
        case speaking
        case error(String)
    }

    // MARK: - Published UI State
    @Published var sessionState: SessionState = .disconnected
    @Published var isInitialized = false
    @Published var audioLevel: Float = 0.0
    @Published var currentStatus = "Initializing..."
    @Published var errorMessage: String?

    @Published var currentTranscript = ""
    @Published var assistantResponse = ""
    @Published var isSpeechDetected = false

    // MARK: - Convenience Properties
    var isListening: Bool { sessionState == .listening }
    var isProcessing: Bool { sessionState == .processing }
    var isSpeaking: Bool { sessionState == .speaking }
    var isActive: Bool {
        switch sessionState {
        case .listening, .processing, .speaking, .connecting:
            return true
        default:
            return false
        }
    }

    // MARK: - Model Selection (for setup UI)
    @Published var sttModel: (framework: InferenceFramework, name: String, id: String)?
    @Published var llmModel: (framework: InferenceFramework, name: String, id: String)?
    @Published var ttsModel: (framework: InferenceFramework, name: String, id: String)?

    @Published var sttModelState: ModelLoadState = .notLoaded
    @Published var llmModelState: ModelLoadState = .notLoaded
    @Published var ttsModelState: ModelLoadState = .notLoaded

    var allModelsLoaded: Bool {
        sttModelState.isLoaded && llmModelState.isLoaded && ttsModelState.isLoaded
    }

    // MARK: - Private
    private var session: VoiceSessionHandle?
    private var eventTask: Task<Void, Never>?

    // MARK: - Initialization

    func initialize() async {
        logger.info("Initializing voice assistant...")

        subscribeToSDKEvents()
        await syncModelStates()

        currentStatus = "Ready"
        isInitialized = true
        logger.info("Voice assistant initialized")
    }

    // MARK: - Model State Sync

    func refreshComponentStatesFromSDK() {
        Task {
            await syncModelStates()
        }
    }

    func syncModelStates() async {
        let states = await RunAnywhere.getVoiceAgentComponentStates()

        sttModelState = mapState(states.stt)
        llmModelState = mapState(states.llm)
        ttsModelState = mapState(states.tts)

        if case .loaded(let id) = states.stt { updateModel(.stt, id: id) }
        if case .loaded(let id) = states.llm { updateModel(.llm, id: id) }
        if case .loaded(let id) = states.tts { updateModel(.tts, id: id) }

        logger.info("States synced - STT:\(states.stt.isLoaded) LLM:\(states.llm.isLoaded) TTS:\(states.tts.isLoaded)")
    }

    private func mapState(_ s: ComponentLoadState) -> ModelLoadState {
        switch s {
        case .notLoaded: return .notLoaded
        case .loading: return .loading
        case .loaded: return .loaded
        case .error(let m): return .error(m)
        }
    }

    private enum ModelType { case stt, llm, tts }

    private func updateModel(_ type: ModelType, id: String) {
        let model = ModelListViewModel.shared.availableModels.first { $0.id == id }
        let name = model?.name ?? id
        let fw = model?.preferredFramework ?? (type == .llm ? .llamaCpp : .onnx)

        switch type {
        case .stt: sttModel = (fw, name, id)
        case .llm: llmModel = (fw, name, id)
        case .tts: ttsModel = (fw, name, id)
        }
    }

    // MARK: - SDK Events

    private func subscribeToSDKEvents() {
        RunAnywhere.events.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in self?.handleSDKEvent(event) }
            .store(in: &cancellables)
    }

    private func handleSDKEvent(_ event: any SDKEvent) {
        if let e = event as? LLMEvent {
            switch e {
            case .modelLoadStarted: llmModelState = .loading
            case .modelLoadCompleted(let id, _, _): llmModelState = .loaded; updateModel(.llm, id: id)
            case .modelLoadFailed(_, let err, _): llmModelState = .error(err)
            case .modelUnloaded: llmModelState = .notLoaded; llmModel = nil
            default: break
            }
        }
        if let e = event as? STTEvent {
            switch e {
            case .modelLoadStarted: sttModelState = .loading
            case .modelLoadCompleted(let id, _, _): sttModelState = .loaded; updateModel(.stt, id: id)
            case .modelLoadFailed(_, let err, _): sttModelState = .error(err)
            case .modelUnloaded: sttModelState = .notLoaded; sttModel = nil
            default: break
            }
        }
        if let e = event as? TTSEvent {
            switch e {
            case .modelLoadStarted: ttsModelState = .loading
            case .modelLoadCompleted(let id, _, _): ttsModelState = .loaded; updateModel(.tts, id: id)
            case .modelLoadFailed(_, let err, _): ttsModelState = .error(err)
            case .modelUnloaded: ttsModelState = .notLoaded; ttsModel = nil
            default: break
            }
        }
    }

    // MARK: - Model Selection

    func setSTTModel(_ model: ModelInfo) {
        sttModel = (model.preferredFramework ?? .onnx, model.name, model.id)
        Task { await syncModelStates() }
    }

    func setLLMModel(_ model: ModelInfo) {
        llmModel = (model.preferredFramework ?? .llamaCpp, model.name, model.id)
        Task { await syncModelStates() }
    }

    func setTTSModel(_ model: ModelInfo) {
        ttsModel = (model.preferredFramework ?? .onnx, model.name, model.id)
        Task { await syncModelStates() }
    }

    // MARK: - Conversation Control

    /// Start voice conversation using SDK's VoiceSession API
    func startConversation() async {
        guard allModelsLoaded else {
            sessionState = .error("Load all models first")
            errorMessage = "Please ensure all models (STT, LLM, TTS) are loaded"
            return
        }

        sessionState = .connecting
        currentStatus = "Connecting..."

        do {
            // Start session - SDK handles everything
            session = try await RunAnywhere.startVoiceSession()
            sessionState = .listening
            currentStatus = "Listening..."
            errorMessage = nil

            // Consume events
            eventTask = Task { [weak self] in
                guard let session = self?.session else { return }
                for await event in session.events {
                    await MainActor.run {
                        self?.handleSessionEvent(event)
                    }
                }
            }

            logger.info("Voice session started")
        } catch {
            sessionState = .error(error.localizedDescription)
            currentStatus = "Error"
            errorMessage = "Failed to start: \(error.localizedDescription)"
            logger.error("Start failed: \(error)")
        }
    }

    /// Stop voice conversation
    func stopConversation() async {
        eventTask?.cancel()
        eventTask = nil

        await session?.stop()
        session = nil

        sessionState = .disconnected
        currentStatus = "Ready"
        audioLevel = 0
        isSpeechDetected = false

        logger.info("Voice session stopped")
    }

    /// Force send current audio (push-to-talk mode)
    func sendNow() async {
        await session?.sendNow()
    }

    // MARK: - Session Event Handling

    private func handleSessionEvent(_ event: VoiceSessionEvent) {
        switch event {
        case .started:
            sessionState = .listening
            currentStatus = "Listening..."

        case .listening(let level):
            audioLevel = level

        case .speechStarted:
            isSpeechDetected = true
            currentStatus = "Listening..."

        case .processing:
            sessionState = .processing
            currentStatus = "Processing..."
            isSpeechDetected = false

        case .transcribed(let text):
            currentTranscript = text

        case .responded(let text):
            assistantResponse = text

        case .speaking:
            sessionState = .speaking
            currentStatus = "Speaking..."

        case .turnCompleted(let transcript, let response, _):
            currentTranscript = transcript
            assistantResponse = response
            sessionState = .listening
            currentStatus = "Listening..."

        case .stopped:
            sessionState = .disconnected
            currentStatus = "Ready"

        case .error(let message):
            logger.error("Session error: \(message)")
            // Don't set error state for processing failures, just continue
        }
    }
}
