//
//  TTSAnalyticsService.swift
//  RunAnywhere SDK
//
//  TTS analytics service.
//  Tracks synthesis operations and metrics.
//  Lifecycle events are handled by ManagedLifecycle.
//

import Foundation

// MARK: - TTS Analytics Service

/// TTS analytics service for tracking synthesis operations.
/// Model lifecycle events (load/unload) are handled by ManagedLifecycle.
public actor TTSAnalyticsService {

    // MARK: - Properties

    private let logger = SDKLogger(category: "TTSAnalytics")

    /// Active synthesis operations
    private var activeSyntheses: [String: SynthesisTracker] = [:]

    /// Metrics
    private var synthesisCount = 0
    private var totalCharacters = 0
    private var totalProcessingTime: Double = 0
    private var totalCharactersPerSecond: Double = 0
    private let startTime = Date()
    private var lastEventTime: Date?

    // MARK: - Types

    private struct SynthesisTracker {
        let id: String
        let startTime: Date
        let voiceId: String
        let text: String
    }

    // MARK: - Initialization

    public init() {}

    // MARK: - Synthesis Tracking

    /// Start tracking a synthesis
    public func startSynthesis(text: String, voice: String, language: String) -> String {
        let id = UUID().uuidString
        activeSyntheses[id] = SynthesisTracker(
            id: id,
            startTime: Date(),
            voiceId: voice,
            text: text
        )

        EventPublisher.shared.track(TTSEvent.synthesisStarted(
            synthesisId: id,
            voiceId: voice,
            text: text
        ))

        logger.debug("Synthesis started: \(id)")
        return id
    }

    /// Track synthesis chunk (analytics only)
    public func trackSynthesisChunk(synthesisId: String, chunkSize: Int) {
        EventPublisher.shared.track(TTSEvent.synthesisChunk(
            synthesisId: synthesisId,
            chunkSize: chunkSize
        ))
    }

    /// Complete a synthesis
    public func completeSynthesis(synthesisId: String, audioDurationMs: Double, audioSizeBytes: Int) {
        guard let tracker = activeSyntheses.removeValue(forKey: synthesisId) else { return }

        let processingTimeMs = Date().timeIntervalSince(tracker.startTime) * 1000
        let characterCount = tracker.text.count
        let charsPerSecond = processingTimeMs > 0 ? Double(characterCount) / (processingTimeMs / 1000.0) : 0

        // Update metrics
        synthesisCount += 1
        totalCharacters += characterCount
        totalProcessingTime += processingTimeMs
        totalCharactersPerSecond += charsPerSecond
        lastEventTime = Date()

        EventPublisher.shared.track(TTSEvent.synthesisCompleted(
            synthesisId: synthesisId,
            voiceId: tracker.voiceId,
            characterCount: characterCount,
            audioSizeBytes: audioSizeBytes,
            durationMs: processingTimeMs
        ))

        logger.debug("Synthesis completed: \(synthesisId)")
    }

    /// Track synthesis failure
    public func trackSynthesisFailed(
        synthesisId: String,
        characterCount: Int,
        processingTimeMs: Double,
        errorMessage: String
    ) {
        activeSyntheses.removeValue(forKey: synthesisId)
        lastEventTime = Date()

        EventPublisher.shared.track(TTSEvent.synthesisFailed(
            synthesisId: synthesisId,
            error: errorMessage
        ))
    }

    /// Track an error during operations
    public func trackError(_ error: Error, operation: String) {
        lastEventTime = Date()
        EventPublisher.shared.track(ErrorEvent.error(
            operation: operation,
            message: error.localizedDescription,
            code: (error as NSError).code
        ))
    }

    // MARK: - Metrics

    public func getMetrics() -> TTSMetrics {
        TTSMetrics(
            totalEvents: synthesisCount,
            startTime: startTime,
            lastEventTime: lastEventTime,
            totalSyntheses: synthesisCount,
            averageCharactersPerSecond: synthesisCount > 0 ? totalCharactersPerSecond / Double(synthesisCount) : 0,
            averageProcessingTimeMs: synthesisCount > 0 ? totalProcessingTime / Double(synthesisCount) : 0,
            totalCharactersProcessed: totalCharacters
        )
    }
}

// MARK: - TTS Metrics

public struct TTSMetrics: AnalyticsMetrics {
    public let totalEvents: Int
    public let startTime: Date
    public let lastEventTime: Date?
    public let totalSyntheses: Int
    public let averageCharactersPerSecond: Double
    public let averageProcessingTimeMs: Double
    public let totalCharactersProcessed: Int

    public init(
        totalEvents: Int = 0,
        startTime: Date = Date(),
        lastEventTime: Date? = nil,
        totalSyntheses: Int = 0,
        averageCharactersPerSecond: Double = 0,
        averageProcessingTimeMs: Double = 0,
        totalCharactersProcessed: Int = 0
    ) {
        self.totalEvents = totalEvents
        self.startTime = startTime
        self.lastEventTime = lastEventTime
        self.totalSyntheses = totalSyntheses
        self.averageCharactersPerSecond = averageCharactersPerSecond
        self.averageProcessingTimeMs = averageProcessingTimeMs
        self.totalCharactersProcessed = totalCharactersProcessed
    }
}
