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

    public var timestamp: Date { Date() }
    public var eventType: SDKEventType { .generation }
}

/// SDK Model Events for public API
public enum SDKModelEvent: SDKEvent {
    // Model loading/unloading
    case loadStarted(modelId: String)
    case loadProgress(modelId: String, progress: Double)
    case loadCompleted(modelId: String)
    case loadFailed(modelId: String, error: Error)
    case unloadStarted
    case unloadCompleted
    case unloadFailed(Error)

    // Model downloads
    case downloadStarted(modelId: String)
    case downloadProgress(modelId: String, progress: Double)
    case downloadCompleted(modelId: String)
    case downloadFailed(modelId: String, error: Error)

    // Model listing/catalog
    case listRequested
    case listCompleted(models: [ModelInfo])
    case listFailed(Error)
    case catalogLoaded(models: [ModelInfo])

    // Model deletion
    case deleteStarted(modelId: String)
    case deleteCompleted(modelId: String)
    case deleteFailed(modelId: String, error: Error)

    // Model registration
    case customModelAdded(name: String, url: String)
    case builtInModelRegistered(modelId: String)

    // Model assignments (from backend)
    case assignmentsFetched(models: [ModelInfo])
    case assignmentsFetchFailed(error: Error)

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
    case pipelineStarted
    case pipelineCompleted
    case vadStarted
    case vadDetected
    case vadEnded
    case sttProcessing
    case llmProcessing
    case ttsProcessing

    public var timestamp: Date { Date() }
    public var eventType: SDKEventType { .voice }
}

/// SDK Performance Events for public API
public enum SDKPerformanceEvent: SDKEvent {
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
    case modelsForFrameworkRequested(framework: InferenceFramework)
    case modelsForFrameworkRetrieved(framework: InferenceFramework, models: [ModelInfo])

    public var timestamp: Date { Date() }
    public var eventType: SDKEventType { .framework }
}

/// SDK Device Events for public API
public enum SDKDeviceEvent: SDKEvent {
    case deviceRegistered(deviceId: String)
    case deviceRegistrationFailed(Error)
    case deviceStateChanged(property: String, newValue: String)

    public var timestamp: Date { Date() }
    public var eventType: SDKEventType { .device }
}
