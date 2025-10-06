import Foundation

/// Base protocol for all SDK events
public protocol SDKEvent {
    var timestamp: Date { get }
    var eventType: SDKEventType { get }
}

/// Event types for categorization
public enum SDKEventType {
    case initialization
    case configuration
    case generation
    case model
    case voice
    case storage
    case framework
    case device
    case error
    case performance
    case network
}

/// SDK Initialization Events for public API
public enum SDKInitializationEvent: SDKEvent {
    case started
    case configurationLoaded(source: String)
    case servicesBootstrapped
    case completed
    case failed(Error)

    public var timestamp: Date { Date() }
    public var eventType: SDKEventType { .initialization }
}

/// SDK Configuration Events for public API
public enum SDKConfigurationEvent: SDKEvent {
    case fetchStarted
    case fetchCompleted(source: String)
    case fetchFailed(Error)
    case loaded(configuration: ConfigurationData?)
    case updated(changes: [String])
    case syncStarted
    case syncCompleted
    case syncFailed(Error)

    // Configuration read events
    case settingsRequested
    case settingsRetrieved(settings: DefaultGenerationSettings)
    case routingPolicyRequested
    case routingPolicyRetrieved(policy: RoutingPolicy)
    case privacyModeRequested
    case privacyModeRetrieved(mode: PrivacyMode)
    case analyticsStatusRequested
    case analyticsStatusRetrieved(enabled: Bool)
    case syncRequested

    public var timestamp: Date { Date() }
    public var eventType: SDKEventType { .configuration }
}

/// SDK Generation Events for public API
public enum SDKGenerationEvent: SDKEvent {
    // Session events
    case sessionStarted(sessionId: String)
    case sessionEnded(sessionId: String)

    // Generation lifecycle
    case started(prompt: String, sessionId: String? = nil)
    case firstTokenGenerated(token: String, latencyMs: Double)
    case tokenGenerated(token: String)
    case streamingUpdate(text: String, tokensCount: Int)
    case completed(response: String, tokensUsed: Int, latencyMs: Double)
    case failed(Error)

    // Model events
    case modelLoaded(modelId: String)
    case modelUnloaded(modelId: String)

    // Cost and routing
    case costCalculated(amount: Double, savedAmount: Double)
    case routingDecision(target: String, reason: String)

    public var timestamp: Date { Date() }
    public var eventType: SDKEventType { .generation }
}

/// SDK Model Events for public API
public enum SDKModelEvent: SDKEvent {
    case loadStarted(modelId: String)
    case loadProgress(modelId: String, progress: Double)
    case loadCompleted(modelId: String)
    case loadFailed(modelId: String, error: Error)
    case unloadStarted
    case unloadCompleted
    case unloadFailed(Error)
    case downloadStarted(modelId: String)
    case downloadProgress(modelId: String, progress: Double)
    case downloadCompleted(modelId: String)
    case downloadFailed(modelId: String, error: Error)
    case listRequested
    case listCompleted(models: [ModelInfo])
    case listFailed(Error)
    case catalogLoaded(models: [ModelInfo])
    case deleteStarted(modelId: String)
    case deleteCompleted(modelId: String)
    case deleteFailed(modelId: String, error: Error)
    case customModelAdded(name: String, url: String)
    case builtInModelRegistered(modelId: String)

    public var timestamp: Date { Date() }
    public var eventType: SDKEventType { .model }
}

/// Voice Events - Unified event system for all voice pipeline operations
public enum SDKVoiceEvent: SDKEvent {
    // MARK: - Pipeline Lifecycle
    case pipelineStarted
    case pipelineCompleted
    case pipelineError(Error)

    // MARK: - VAD (Voice Activity Detection) Events
    case vadStarted
    case vadSpeechStart
    case vadSpeechEnd
    case vadDetected
    case vadEnded
    case vadAudioLevel(Float)

    // MARK: - STT (Speech-to-Text) Events
    case transcriptionStarted
    case transcriptionPartial(text: String)
    case transcriptionFinal(text: String)
    case languageDetected(String)
    case sttProcessing

    // MARK: - STT with Speaker Diarization
    case transcriptionPartialWithSpeaker(text: String, speaker: SpeakerInfo)
    case transcriptionFinalWithSpeaker(text: String, speaker: SpeakerInfo)
    case newSpeakerDetected(SpeakerInfo)
    case speakerChanged(from: SpeakerInfo?, to: SpeakerInfo)

    // MARK: - LLM (Language Model) Events
    case llmStarted
    case llmThinking
    case llmStreamStarted
    case llmStreamToken(String)
    case llmPartialResponse(String)
    case llmFinalResponse(String)
    case llmProcessing
    case responseGenerated(text: String)

    // MARK: - TTS (Text-to-Speech) Events
    case synthesisStarted
    case ttsAudioChunk(Data)
    case audioGenerated(data: Data)
    case synthesisCompleted
    case ttsProcessing

    // MARK: - Component Initialization Events
    case componentInitializing(String)
    case componentInitialized(String)
    case componentInitializationFailed(String, Error)
    case allComponentsInitialized

    // MARK: - Session and Conversation Events
    case conversationInitialized
    case conversationTranscribing
    case conversationTranscribed(String)
    case conversationGenerating
    case conversationGenerated(String)
    case conversationSynthesizing
    case conversationSynthesized(Data)
    case conversationError(Error)

    // MARK: - Legacy Compatibility Events
    case listeningStarted
    case listeningEnded
    case speechDetected

    // MARK: - Voice Agent Events
    case voiceAgentProcessed(result: VoiceAgentResult)
    case voiceAgentTriggered(Bool)
    case voiceAgentTranscriptionAvailable(String)
    case voiceAgentResponseGenerated(String)
    case voiceAgentAudioSynthesized(Data)

    public var timestamp: Date { Date() }
    public var eventType: SDKEventType { .voice }
}

/// SDK Performance Events for public API
public enum SDKPerformanceEvent: SDKEvent {
    case memoryWarning(usage: Int64)
    case thermalStateChanged(state: String)
    case latencyMeasured(operation: String, milliseconds: Double)
    case throughputMeasured(tokensPerSecond: Double)

    public var timestamp: Date { Date() }
    public var eventType: SDKEventType { .performance }
}

/// SDK Network Events for public API
public enum SDKNetworkEvent: SDKEvent {
    case requestStarted(url: String)
    case requestCompleted(url: String, statusCode: Int)
    case requestFailed(url: String, error: Error)
    case connectivityChanged(isOnline: Bool)

    public var timestamp: Date { Date() }
    public var eventType: SDKEventType { .network }
}

/// SDK Storage Events for public API
public enum SDKStorageEvent: SDKEvent {
    case infoRequested
    case infoRetrieved(info: StorageInfo)
    case modelsRequested
    case modelsRetrieved(models: [StoredModel])
    case clearCacheStarted
    case clearCacheCompleted
    case clearCacheFailed(Error)
    case cleanTempStarted
    case cleanTempCompleted
    case cleanTempFailed(Error)
    case deleteModelStarted(modelId: String)
    case deleteModelCompleted(modelId: String)
    case deleteModelFailed(modelId: String, error: Error)

    public var timestamp: Date { Date() }
    public var eventType: SDKEventType { .storage }
}

/// SDK Framework Events for public API
public enum SDKFrameworkEvent: SDKEvent {
    case adapterRegistered(framework: LLMFramework, name: String)
    case adaptersRequested
    case adaptersRetrieved(count: Int)
    case frameworksRequested
    case frameworksRetrieved(frameworks: [LLMFramework])
    case availabilityRequested
    case availabilityRetrieved(availability: [FrameworkAvailability])
    case modelsForFrameworkRequested(framework: LLMFramework)
    case modelsForFrameworkRetrieved(framework: LLMFramework, models: [ModelInfo])
    case frameworksForModalityRequested(modality: FrameworkModality)
    case frameworksForModalityRetrieved(modality: FrameworkModality, frameworks: [LLMFramework])

    public var timestamp: Date { Date() }
    public var eventType: SDKEventType { .framework }
}

/// SDK Device Events for public API
public enum SDKDeviceEvent: SDKEvent {
    case deviceInfoCollected(deviceInfo: DeviceInfoData)
    case deviceInfoCollectionFailed(Error)
    case deviceInfoRefreshed(deviceInfo: DeviceInfoData)
    case deviceInfoSyncStarted
    case deviceInfoSyncCompleted
    case deviceInfoSyncFailed(Error)
    case deviceStateChanged(property: String, newValue: String)

    public var timestamp: Date { Date() }
    public var eventType: SDKEventType { .device }
}

/// Events for component initialization lifecycle
public enum ComponentInitializationEvent: SDKEvent {
    // Overall initialization
    case initializationStarted(components: [SDKComponent])
    case initializationCompleted(result: InitializationResult)

    // Component-specific events
    case componentStateChanged(component: SDKComponent, oldState: ComponentState, newState: ComponentState)
    case componentChecking(component: SDKComponent, modelId: String?)
    case componentDownloadRequired(component: SDKComponent, modelId: String, sizeBytes: Int64)
    case componentDownloadStarted(component: SDKComponent, modelId: String)
    case componentDownloadProgress(component: SDKComponent, modelId: String, progress: Double)
    case componentDownloadCompleted(component: SDKComponent, modelId: String)
    case componentInitializing(component: SDKComponent, modelId: String?)
    case componentReady(component: SDKComponent, modelId: String?)
    case componentFailed(component: SDKComponent, error: Error)

    // Batch events
    case parallelInitializationStarted(components: [SDKComponent])
    case sequentialInitializationStarted(components: [SDKComponent])
    case allComponentsReady
    case someComponentsReady(ready: [SDKComponent], pending: [SDKComponent])

    public var timestamp: Date { Date() }
    public var eventType: SDKEventType { .initialization }

    /// Extract component from event if applicable
    public var component: SDKComponent? {
        switch self {
        case .componentStateChanged(let component, _, _),
             .componentChecking(let component, _),
             .componentDownloadRequired(let component, _, _),
             .componentDownloadStarted(let component, _),
             .componentDownloadProgress(let component, _, _),
             .componentDownloadCompleted(let component, _),
             .componentInitializing(let component, _),
             .componentReady(let component, _),
             .componentFailed(let component, _):
            return component
        default:
            return nil
        }
    }
}
