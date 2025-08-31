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

    // New configuration events
    case updateRequested(request: RunAnywhere.ConfigurationRequest)
    case updateCompleted
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

/// Voice Events
public enum SDKVoiceEvent: SDKEvent {
    case listeningStarted
    case listeningEnded
    case speechDetected
    case transcriptionStarted
    case transcriptionPartial(text: String)
    case transcriptionFinal(text: String)
    case responseGenerated(text: String)
    case synthesisStarted
    case audioGenerated(data: Data)
    case synthesisCompleted
    case pipelineError(Error)
    case pipelineCreated(config: ModularPipelineConfig)
    case pipelineStarted(config: ModularPipelineConfig)
    case pipelineEvent(ModularPipelineEvent)
    case pipelineCompleted

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
