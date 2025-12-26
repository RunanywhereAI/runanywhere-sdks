//
//  ManagedLifecycle.swift
//  RunAnywhere SDK
//
//  Unified lifecycle management with integrated event tracking.
//  Tracks lifecycle events directly via EventPublisher.
//

import Foundation

// MARK: - Managed Lifecycle

/// Actor that wraps ModelLifecycleManager with integrated event tracking.
///
/// Lifecycle events (load, unload) are published directly to EventPublisher,
/// which routes them to both public EventBus and Analytics automatically.
public actor ManagedLifecycle<ServiceType> {

    // MARK: - Properties

    private let lifecycle: ModelLifecycleManager<ServiceType>
    private let resourceType: CapabilityResourceType
    private let logger: SDKLogger

    // Metrics
    private var loadCount = 0
    private var totalLoadTime: TimeInterval = 0
    private let startTime = Date()

    // MARK: - Initialization

    public init(
        lifecycle: ModelLifecycleManager<ServiceType>,
        resourceType: CapabilityResourceType,
        loggerCategory: String
    ) {
        self.lifecycle = lifecycle
        self.resourceType = resourceType
        self.logger = SDKLogger(category: loggerCategory)
    }

    // MARK: - State Properties

    public var isLoaded: Bool {
        get async { await lifecycle.isLoaded }
    }

    public var currentModelId: String? {
        get async { await lifecycle.currentResourceId }
    }

    public var currentService: ServiceType? {
        get async { await lifecycle.currentService }
    }

    public var state: CapabilityLoadingState {
        get async { await lifecycle.state }
    }

    // MARK: - Configuration

    public func configure(_ config: (any ComponentConfiguration)?) async {
        await lifecycle.configure(config)
    }

    // MARK: - Lifecycle Operations

    /// Load a model with automatic event tracking.
    @discardableResult
    public func load(_ modelId: String) async throws -> ServiceType {
        // Check if already loaded with same ID - skip duplicate events
        if await lifecycle.currentResourceId == modelId, let service = await lifecycle.currentService {
            logger.info("Model already loaded, skipping duplicate load: \(modelId)")
            return service
        }

        let startTime = Date()
        logger.info("Loading \(resourceType.rawValue): \(modelId)")

        // Track load started (only if not already loaded)
        trackEvent(type: .loadStarted, modelId: modelId)

        do {
            let service = try await lifecycle.load(modelId)
            let loadTime = Date().timeIntervalSince(startTime)

            // Track load completed
            trackEvent(type: .loadCompleted, modelId: modelId, durationMs: loadTime * 1000)

            // Update metrics
            loadCount += 1
            totalLoadTime += loadTime

            logger.info("Loaded \(resourceType.rawValue): \(modelId) in \(Int(loadTime * 1000))ms")
            return service
        } catch {
            let loadTime = Date().timeIntervalSince(startTime)

            // Track load failed
            trackEvent(type: .loadFailed, modelId: modelId, durationMs: loadTime * 1000, error: error)

            logger.error("Failed to load \(resourceType.rawValue): \(error)")
            throw error
        }
    }

    /// Unload the currently loaded model.
    public func unload() async {
        if let modelId = await lifecycle.currentResourceId {
            logger.info("Unloading \(resourceType.rawValue): \(modelId)")
            await lifecycle.unload()
            trackEvent(type: .unloaded, modelId: modelId)
        } else {
            await lifecycle.unload()
        }
    }

    /// Reset all state.
    public func reset() async {
        if let modelId = await lifecycle.currentResourceId {
            trackEvent(type: .unloaded, modelId: modelId)
        }
        await lifecycle.reset()
    }

    /// Get service or throw if not loaded.
    public func requireService() async throws -> ServiceType {
        try await lifecycle.requireService()
    }

    /// Track an operation error with full SDKError context.
    public func trackOperationError(_ error: Error, operation: String) {
        let errorEvent = SDKErrorEvent.from(error, operation: operation)
        EventPublisher.shared.track(errorEvent)
    }

    /// Get current model ID with fallback.
    public func modelIdOrUnknown() async -> String {
        await lifecycle.currentResourceId ?? "unknown"
    }

    // MARK: - Metrics

    public func getLifecycleMetrics() -> ModelLifecycleMetrics {
        ModelLifecycleMetrics(
            totalEvents: loadCount,
            startTime: startTime,
            lastEventTime: nil,
            totalLoads: loadCount,
            successfulLoads: loadCount,
            failedLoads: 0,
            averageLoadTimeMs: loadCount > 0 ? (totalLoadTime * 1000) / Double(loadCount) : 0,
            totalUnloads: 0,
            totalDownloads: 0,
            successfulDownloads: 0,
            failedDownloads: 0,
            totalBytesDownloaded: 0
        )
    }

    // MARK: - Private Event Tracking

    private enum LifecycleEventType {
        case loadStarted
        case loadCompleted
        case loadFailed
        case unloaded
    }

    private func trackEvent(
        type: LifecycleEventType,
        modelId: String,
        durationMs: Double? = nil,
        error: Error? = nil
    ) {
        // Look up the framework from the model registry
        let framework = lookupFramework(for: modelId)

        // Create the appropriate event based on resource type
        let event: any SDKEvent = createEvent(
            type: type,
            modelId: modelId,
            durationMs: durationMs,
            error: error,
            framework: framework
        )

        // Track via EventPublisher - routes to both EventBus and Analytics
        EventPublisher.shared.track(event)
    }

    /// Look up the framework for a model from the registry
    private func lookupFramework(for modelId: String) -> InferenceFramework {
        guard let modelInfo = ServiceContainer.shared.modelRegistry.getModel(by: modelId) else {
            return .unknown
        }
        return modelInfo.framework
    }

    private func createEvent(
        type: LifecycleEventType,
        modelId: String,
        durationMs: Double?,
        error: Error?,
        framework: InferenceFramework
    ) -> any SDKEvent {
        switch resourceType {
        case .llmModel:
            return createLLMEvent(type: type, modelId: modelId, durationMs: durationMs, error: error, framework: framework)
        case .sttModel:
            return createSTTEvent(type: type, modelId: modelId, durationMs: durationMs, error: error, framework: framework)
        case .ttsVoice:
            return createTTSEvent(type: type, modelId: modelId, durationMs: durationMs, error: error, framework: framework)
        case .vadModel, .diarizationModel:
            // Use generic model event for VAD and diarization
            return createModelEvent(type: type, modelId: modelId, durationMs: durationMs, error: error)
        }
    }

    private func createLLMEvent(
        type: LifecycleEventType,
        modelId: String,
        durationMs: Double?,
        error: Error?,
        framework: InferenceFramework
    ) -> LLMEvent {
        switch type {
        case .loadStarted:
            return .modelLoadStarted(modelId: modelId, framework: framework)
        case .loadCompleted:
            return .modelLoadCompleted(modelId: modelId, durationMs: durationMs ?? 0, framework: framework)
        case .loadFailed:
            return .modelLoadFailed(modelId: modelId, error: SDKError.from(error, category: .llm), framework: framework)
        case .unloaded:
            return .modelUnloaded(modelId: modelId)
        }
    }

    private func createSTTEvent(
        type: LifecycleEventType,
        modelId: String,
        durationMs: Double?,
        error: Error?,
        framework: InferenceFramework
    ) -> STTEvent {
        switch type {
        case .loadStarted:
            return .modelLoadStarted(modelId: modelId, framework: framework)
        case .loadCompleted:
            return .modelLoadCompleted(modelId: modelId, durationMs: durationMs ?? 0, framework: framework)
        case .loadFailed:
            return .modelLoadFailed(modelId: modelId, error: SDKError.from(error, category: .stt), framework: framework)
        case .unloaded:
            return .modelUnloaded(modelId: modelId)
        }
    }

    private func createTTSEvent(
        type: LifecycleEventType,
        modelId: String,
        durationMs: Double?,
        error: Error?,
        framework: InferenceFramework
    ) -> TTSEvent {
        switch type {
        case .loadStarted:
            return .modelLoadStarted(modelId: modelId, framework: framework)
        case .loadCompleted:
            return .modelLoadCompleted(modelId: modelId, durationMs: durationMs ?? 0, framework: framework)
        case .loadFailed:
            return .modelLoadFailed(modelId: modelId, error: SDKError.from(error, category: .tts), framework: framework)
        case .unloaded:
            return .modelUnloaded(modelId: modelId)
        }
    }

    private func createModelEvent(
        type: LifecycleEventType,
        modelId: String,
        durationMs: Double?,
        error: Error?
    ) -> ModelEvent {
        switch type {
        case .loadStarted:
            return .downloadStarted(modelId: modelId) // Reuse download as generic load
        case .loadCompleted:
            return .downloadCompleted(modelId: modelId, durationMs: durationMs ?? 0, sizeBytes: 0)
        case .loadFailed:
            return .downloadFailed(modelId: modelId, error: SDKError.from(error, category: .download))
        case .unloaded:
            return .deleted(modelId: modelId)
        }
    }
}

// MARK: - Factory Extensions

extension ManagedLifecycle where ServiceType == LLMService {
    public static func forLLM() -> ManagedLifecycle<LLMService> {
        ManagedLifecycle(
            lifecycle: ModelLifecycleManager.forLLM(),
            resourceType: .llmModel,
            loggerCategory: "LLM.Lifecycle"
        )
    }
}

extension ManagedLifecycle where ServiceType == STTService {
    public static func forSTT() -> ManagedLifecycle<STTService> {
        ManagedLifecycle(
            lifecycle: ModelLifecycleManager.forSTT(),
            resourceType: .sttModel,
            loggerCategory: "STT.Lifecycle"
        )
    }
}

extension ManagedLifecycle where ServiceType == TTSService {
    public static func forTTS() -> ManagedLifecycle<TTSService> {
        ManagedLifecycle(
            lifecycle: ModelLifecycleManager.forTTS(),
            resourceType: .ttsVoice,
            loggerCategory: "TTS.Lifecycle"
        )
    }
}
