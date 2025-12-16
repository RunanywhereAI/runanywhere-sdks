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

    public var currentResourceId: String? {
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

    /// Load a resource with automatic event tracking.
    @discardableResult
    public func load(_ resourceId: String) async throws -> ServiceType {
        let startTime = Date()
        logger.info("Loading \(resourceType.rawValue): \(resourceId)")

        // Track load started
        trackEvent(type: .loadStarted, resourceId: resourceId)

        do {
            let service = try await lifecycle.load(resourceId)
            let loadTime = Date().timeIntervalSince(startTime)

            // Track load completed
            trackEvent(type: .loadCompleted, resourceId: resourceId, durationMs: loadTime * 1000)

            // Update metrics
            loadCount += 1
            totalLoadTime += loadTime

            logger.info("Loaded \(resourceType.rawValue): \(resourceId) in \(Int(loadTime * 1000))ms")
            return service
        } catch {
            let loadTime = Date().timeIntervalSince(startTime)

            // Track load failed
            trackEvent(type: .loadFailed, resourceId: resourceId, durationMs: loadTime * 1000, error: error)

            logger.error("Failed to load \(resourceType.rawValue): \(error)")
            throw error
        }
    }

    /// Unload the currently loaded resource.
    public func unload() async {
        if let resourceId = await lifecycle.currentResourceId {
            logger.info("Unloading \(resourceType.rawValue): \(resourceId)")
            await lifecycle.unload()
            trackEvent(type: .unloaded, resourceId: resourceId)
        } else {
            await lifecycle.unload()
        }
    }

    /// Reset all state.
    public func reset() async {
        if let resourceId = await lifecycle.currentResourceId {
            trackEvent(type: .unloaded, resourceId: resourceId)
        }
        await lifecycle.reset()
    }

    /// Get service or throw if not loaded.
    public func requireService() async throws -> ServiceType {
        try await lifecycle.requireService()
    }

    /// Track an operation error.
    public func trackOperationError(_ error: Error, operation: String) {
        EventPublisher.shared.track(ErrorEvent.error(
            operation: operation,
            message: error.localizedDescription,
            code: (error as NSError).code
        ))
    }

    /// Get current resource ID with fallback.
    public func resourceIdOrUnknown() async -> String {
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
        resourceId: String,
        durationMs: Double? = nil,
        error: Error? = nil
    ) {
        // Create the appropriate event based on resource type
        let event: any SDKEvent = createEvent(
            type: type,
            resourceId: resourceId,
            durationMs: durationMs,
            error: error
        )

        // Track via EventPublisher - routes to both EventBus and Analytics
        EventPublisher.shared.track(event)
    }

    private func createEvent(
        type: LifecycleEventType,
        resourceId: String,
        durationMs: Double?,
        error: Error?
    ) -> any SDKEvent {
        switch resourceType {
        case .llmModel:
            return createLLMEvent(type: type, resourceId: resourceId, durationMs: durationMs, error: error)
        case .sttModel:
            return createSTTEvent(type: type, resourceId: resourceId, durationMs: durationMs, error: error)
        case .ttsVoice:
            return createTTSEvent(type: type, resourceId: resourceId, durationMs: durationMs, error: error)
        case .vadModel, .diarizationModel:
            // Use generic model event for VAD and diarization
            return createModelEvent(type: type, resourceId: resourceId, durationMs: durationMs, error: error)
        }
    }

    private func createLLMEvent(
        type: LifecycleEventType,
        resourceId: String,
        durationMs: Double?,
        error: Error?
    ) -> LLMEvent {
        switch type {
        case .loadStarted:
            return .modelLoadStarted(modelId: resourceId)
        case .loadCompleted:
            return .modelLoadCompleted(modelId: resourceId, durationMs: durationMs ?? 0)
        case .loadFailed:
            return .modelLoadFailed(modelId: resourceId, error: error?.localizedDescription ?? "Unknown error")
        case .unloaded:
            return .modelUnloaded(modelId: resourceId)
        }
    }

    private func createSTTEvent(
        type: LifecycleEventType,
        resourceId: String,
        durationMs: Double?,
        error: Error?
    ) -> STTEvent {
        switch type {
        case .loadStarted:
            return .modelLoadStarted(modelId: resourceId)
        case .loadCompleted:
            return .modelLoadCompleted(modelId: resourceId, durationMs: durationMs ?? 0)
        case .loadFailed:
            return .modelLoadFailed(modelId: resourceId, error: error?.localizedDescription ?? "Unknown error")
        case .unloaded:
            return .modelUnloaded(modelId: resourceId)
        }
    }

    private func createTTSEvent(
        type: LifecycleEventType,
        resourceId: String,
        durationMs: Double?,
        error: Error?
    ) -> TTSEvent {
        switch type {
        case .loadStarted:
            return .modelLoadStarted(voiceId: resourceId)
        case .loadCompleted:
            return .modelLoadCompleted(voiceId: resourceId, durationMs: durationMs ?? 0)
        case .loadFailed:
            return .modelLoadFailed(voiceId: resourceId, error: error?.localizedDescription ?? "Unknown error")
        case .unloaded:
            return .modelUnloaded(voiceId: resourceId)
        }
    }

    private func createModelEvent(
        type: LifecycleEventType,
        resourceId: String,
        durationMs: Double?,
        error: Error?
    ) -> ModelEvent {
        switch type {
        case .loadStarted:
            return .downloadStarted(modelId: resourceId) // Reuse download as generic load
        case .loadCompleted:
            return .downloadCompleted(modelId: resourceId, durationMs: durationMs ?? 0, sizeBytes: 0)
        case .loadFailed:
            return .downloadFailed(modelId: resourceId, error: error?.localizedDescription ?? "Unknown error")
        case .unloaded:
            return .deleted(modelId: resourceId)
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
