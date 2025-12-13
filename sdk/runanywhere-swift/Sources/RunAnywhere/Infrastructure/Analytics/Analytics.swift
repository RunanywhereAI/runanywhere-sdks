//
//  Analytics.swift
//  RunAnywhere SDK
//
//  Public entry point for the Analytics capability
//  Provides a unified facade for analytics, telemetry, and event tracking
//

import Foundation

/// Public entry point for the Analytics capability
/// Provides simplified access to analytics, telemetry, and event tracking operations
public final class Analytics {

    // MARK: - Shared Instance

    /// Shared singleton instance for convenient access
    public static let shared = Analytics()

    // MARK: - Properties

    private let queueManager: AnalyticsQueueManager
    private let logger = SDKLogger(category: "Analytics")
    private var configuration: AnalyticsConfiguration

    // MARK: - Capability-Specific Analytics

    /// STT-specific analytics service
    public private(set) var stt: STTAnalyticsService?

    /// TTS-specific analytics service
    public private(set) var tts: TTSAnalyticsService?

    /// Generation-specific analytics service
    public private(set) var generation: GenerationAnalyticsService?

    /// Voice-specific analytics service
    public private(set) var voice: VoiceAnalyticsService?

    // MARK: - Initialization

    /// Initialize with default configuration
    public convenience init() {
        self.init(configuration: .default)
    }

    /// Initialize with custom configuration
    /// - Parameter configuration: The analytics configuration
    public init(configuration: AnalyticsConfiguration) {
        self.configuration = configuration
        self.queueManager = AnalyticsQueueManager.shared
        logger.debug("Analytics initialized with configuration")
    }

    /// Initialize the analytics system with a telemetry repository
    /// - Parameter telemetryRepository: The repository for telemetry persistence
    public func initialize(telemetryRepository: TelemetryRepositoryImpl) async {
        await queueManager.initialize(telemetryRepository: telemetryRepository)
        logger.info("Analytics system initialized with telemetry repository")
    }

    // MARK: - Public API - Queue Manager

    /// Access the underlying queue manager
    /// Provides low-level queue operations if needed
    public var underlyingQueueManager: AnalyticsQueueManager {
        return queueManager
    }

    // MARK: - Public API - Event Tracking

    /// Track an analytics event through the queue
    /// - Parameter event: The event to track
    public func track(event: any AnalyticsEvent) async {
        logger.debug("Tracking event: \(event.type)")
        await queueManager.enqueue(event)
    }

    /// Track multiple analytics events at once
    /// - Parameter events: Array of events to track
    public func trackBatch(events: [any AnalyticsEvent]) async {
        logger.debug("Tracking batch of \(events.count) events")
        await queueManager.enqueueBatch(events)
    }

    /// Force flush all pending events
    public func flush() async {
        logger.info("Flushing pending analytics events")
        await queueManager.flush()
    }

    // MARK: - Capability Registration

    /// Register STT analytics service
    /// - Parameter service: The STT analytics service instance
    public func registerSTTAnalytics(_ service: STTAnalyticsService) {
        self.stt = service
        logger.debug("STT analytics service registered")
    }

    /// Register TTS analytics service
    /// - Parameter service: The TTS analytics service instance
    public func registerTTSAnalytics(_ service: TTSAnalyticsService) {
        self.tts = service
        logger.debug("TTS analytics service registered")
    }

    /// Register Generation analytics service
    /// - Parameter service: The Generation analytics service instance
    public func registerGenerationAnalytics(_ service: GenerationAnalyticsService) {
        self.generation = service
        logger.debug("Generation analytics service registered")
    }

    /// Register Voice analytics service
    /// - Parameter service: The Voice analytics service instance
    public func registerVoiceAnalytics(_ service: VoiceAnalyticsService) {
        self.voice = service
        logger.debug("Voice analytics service registered")
    }

    // MARK: - Configuration

    /// Update analytics configuration
    /// - Parameter configuration: New configuration to apply
    public func updateConfiguration(_ configuration: AnalyticsConfiguration) throws {
        try configuration.validate()
        self.configuration = configuration
        logger.info("Analytics configuration updated")
    }

    /// Get current analytics configuration
    public var currentConfiguration: AnalyticsConfiguration {
        return configuration
    }
}

// MARK: - Convenience Extensions

extension Analytics {

    /// Track a simple custom event with properties
    /// - Parameters:
    ///   - type: Event type string
    ///   - properties: Additional event properties
    public func trackCustomEvent(
        type: String,
        sessionId: String? = nil,
        properties: [String: String] = [:]
    ) async {
        let eventData = CustomEventData(properties: properties)
        let event = GenericAnalyticsEvent(
            type: type,
            sessionId: sessionId,
            eventData: eventData
        )
        await track(event: event)
    }

    /// Track an error event
    /// - Parameters:
    ///   - error: The error that occurred
    ///   - context: Context where the error occurred
    ///   - file: Source file where error occurred
    ///   - line: Line number where error occurred
    ///   - function: Function name where error occurred
    public func trackError(
        _ error: Error,
        context: AnalyticsContext,
        file: String = #file,
        line: Int = #line,
        function: String = #function
    ) async {
        let eventData = ErrorEventData(
            from: error,
            context: context,
            file: file,
            line: line,
            function: function
        )
        let event = GenericAnalyticsEvent(
            type: "error",
            eventData: eventData
        )
        await track(event: event)
    }
}

// MARK: - Supporting Types

/// Generic analytics event for simple event tracking
public struct GenericAnalyticsEvent: AnalyticsEvent {
    public let id: String
    public let type: String
    public let timestamp: Date
    public let sessionId: String?
    public let eventData: any AnalyticsEventData

    public init(
        type: String,
        sessionId: String? = nil,
        eventData: any AnalyticsEventData
    ) {
        self.id = UUID().uuidString
        self.type = type
        self.timestamp = Date()
        self.sessionId = sessionId
        self.eventData = eventData
    }
}

/// Custom event data for simple property tracking
public struct CustomEventData: AnalyticsEventData {
    public let properties: [String: String]

    public init(properties: [String: String]) {
        self.properties = properties
    }
}
