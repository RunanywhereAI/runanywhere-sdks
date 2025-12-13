//
//  TTSAnalyticsService.swift
//  RunAnywhere SDK
//
//  TTS-specific analytics service with enterprise telemetry support
//

import Foundation

// MARK: - TTS Analytics Service

/// TTS analytics service with enterprise telemetry support
public actor TTSAnalyticsService: AnalyticsService {

    // MARK: - Type Aliases
    public typealias Event = TTSEvent
    public typealias Metrics = TTSMetrics

    // MARK: - Properties

    private let queueManager: AnalyticsQueueManager
    private let logger: SDKLogger
    private var currentSession: SessionInfo?
    private var events: [TTSEvent] = []

    private struct SessionInfo {
        let id: String
        let modelId: String?
        let voice: String?
        let startTime: Date
    }

    private var metrics = TTSMetrics()
    private var synthesisCount = 0
    private var totalCharacters = 0
    private var totalProcessingTime: Double = 0
    private var totalCharactersPerSecond: Double = 0

    // Synthesis tracking
    private var activeSyntheses: [String: SynthesisTracker] = [:]

    private struct SynthesisTracker {
        let id: String
        let startTime: Date
        let characterCount: Int
        let voice: String
        let language: String
    }

    // MARK: - Initialization

    public init(queueManager: AnalyticsQueueManager = .shared) {
        self.queueManager = queueManager
        self.logger = SDKLogger(category: "TTSAnalytics")
    }

    // MARK: - Analytics Service Protocol

    public func track(event: TTSEvent) async {
        events.append(event)
        await queueManager.enqueue(event)
        await processEvent(event)
    }

    public func trackBatch(events: [TTSEvent]) async {
        self.events.append(contentsOf: events)
        await queueManager.enqueueBatch(events)
        for event in events {
            await processEvent(event)
        }
    }

    public func getMetrics() async -> TTSMetrics {
        return TTSMetrics(
            totalEvents: events.count,
            startTime: metrics.startTime,
            lastEventTime: events.last?.timestamp,
            totalSyntheses: synthesisCount,
            averageCharactersPerSecond: synthesisCount > 0 ? totalCharactersPerSecond / Double(synthesisCount) : 0,
            averageProcessingTimeMs: synthesisCount > 0 ? totalProcessingTime / Double(synthesisCount) : 0,
            totalCharactersProcessed: totalCharacters
        )
    }

    public func clearMetrics(olderThan date: Date) async {
        events.removeAll { event in
            event.timestamp < date
        }
    }

    public func startSession(metadata: SessionMetadata) async -> String {
        let sessionInfo = SessionInfo(
            id: metadata.id,
            modelId: metadata.modelId,
            voice: nil,
            startTime: Date()
        )
        currentSession = sessionInfo
        return metadata.id
    }

    public func endSession(sessionId: String) async {
        if currentSession?.id == sessionId {
            currentSession = nil
        }
    }

    public func isHealthy() async -> Bool {
        return true
    }

    // MARK: - TTS-Specific Methods (Local Analytics)

    /// Start tracking a synthesis operation
    public func startSynthesis(
        synthesisId: String? = nil,
        text: String,
        voice: String,
        language: String
    ) async -> String {
        let id = synthesisId ?? UUID().uuidString

        let tracker = SynthesisTracker(
            id: id,
            startTime: Date(),
            characterCount: text.count,
            voice: voice,
            language: language
        )
        activeSyntheses[id] = tracker

        let eventData = TTSSynthesisStartData(
            characterCount: text.count,
            voice: voice,
            language: language
        )
        let event = TTSEvent(
            type: .synthesisStarted,
            sessionId: currentSession?.id,
            eventData: eventData
        )
        await track(event: event)

        return id
    }

    /// Complete a synthesis operation
    public func completeSynthesis(
        synthesisId: String,
        audioDurationMs: Double,
        audioSizeBytes: Int
    ) async {
        guard let tracker = activeSyntheses[synthesisId] else { return }

        let processingTimeMs = Date().timeIntervalSince(tracker.startTime) * 1000

        let eventData = TTSSynthesisCompletionData(
            characterCount: tracker.characterCount,
            audioDurationMs: audioDurationMs,
            audioSizeBytes: audioSizeBytes,
            processingTimeMs: processingTimeMs
        )
        let event = TTSEvent(
            type: .synthesisCompleted,
            sessionId: currentSession?.id,
            eventData: eventData
        )
        await track(event: event)

        // Update metrics
        synthesisCount += 1
        totalCharacters += tracker.characterCount
        totalProcessingTime += processingTimeMs
        totalCharactersPerSecond += eventData.charactersPerSecond

        // Clean up tracker
        activeSyntheses.removeValue(forKey: synthesisId)
    }

    /// Track synthesis start (legacy method for backward compatibility)
    public func trackSynthesisStarted(text: String, voice: String, language: String) async {
        _ = await startSynthesis(text: text, voice: voice, language: language)
    }

    /// Track synthesis completion (legacy method for backward compatibility)
    public func trackSynthesisCompleted(
        characterCount: Int,
        audioDurationMs: Double,
        audioSizeBytes: Int,
        processingTimeMs: Double
    ) async {
        let eventData = TTSSynthesisCompletionData(
            characterCount: characterCount,
            audioDurationMs: audioDurationMs,
            audioSizeBytes: audioSizeBytes,
            processingTimeMs: processingTimeMs
        )
        let event = TTSEvent(
            type: .synthesisCompleted,
            sessionId: currentSession?.id,
            eventData: eventData
        )
        await track(event: event)

        // Update metrics
        synthesisCount += 1
        totalCharacters += characterCount
        totalProcessingTime += processingTimeMs
        totalCharactersPerSecond += eventData.charactersPerSecond
    }

    /// Track error
    public func trackError(error: Error, context: AnalyticsContext) async {
        let eventData = ErrorEventData(
            error: error.localizedDescription,
            context: context
        )
        let event = TTSEvent(
            type: .error,
            sessionId: currentSession?.id,
            eventData: eventData
        )
        await track(event: event)
    }

    /// Track synthesis failure
    public func trackSynthesisFailed(
        synthesisId: String,
        characterCount: Int,
        processingTimeMs: Double,
        errorMessage: String
    ) async {
        let eventData = TTSSynthesisFailureData(
            synthesisId: synthesisId,
            characterCount: characterCount,
            processingTimeMs: processingTimeMs,
            errorMessage: errorMessage
        )
        let event = TTSEvent(
            type: .error,
            sessionId: currentSession?.id,
            eventData: eventData
        )
        await track(event: event)

        // Clean up any active tracker
        activeSyntheses.removeValue(forKey: synthesisId)
    }

    /// Track model loading
    public func trackModelLoading(
        modelId: String,
        loadTime: TimeInterval,
        success: Bool
    ) async {
        let eventData = TTSModelLoadingData(
            modelId: modelId,
            loadTimeMs: loadTime * 1000,
            success: success
        )
        let event = TTSEvent(
            type: success ? .modelLoaded : .modelLoadFailed,
            sessionId: currentSession?.id,
            eventData: eventData
        )

        await track(event: event)
    }

    // MARK: - Private Methods

    private func processEvent(_ event: TTSEvent) async {
        // Custom processing for TTS events if needed
    }
}
