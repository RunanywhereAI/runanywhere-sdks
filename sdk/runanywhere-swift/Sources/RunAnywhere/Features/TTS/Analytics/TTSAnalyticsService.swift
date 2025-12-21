//
//  TTSAnalyticsService.swift
//  RunAnywhere SDK
//
//  TTS analytics service.
//  Tracks synthesis operations and metrics.
//  Lifecycle events are handled by ManagedLifecycle.
//
//  NOTE: ⚠️ Audio duration estimation assumes 16-bit PCM @ 22050Hz (standard for TTS).
//  Formula: audioDurationMs = (bytes / 2) / 22050 * 1000
//  Actual sample rates may vary depending on the TTS model/voice configuration.
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
    private var totalProcessingTimeMs: Double = 0
    private var totalAudioDurationMs: Double = 0
    private var totalAudioSizeBytes: Int64 = 0
    private var totalCharactersPerSecond: Double = 0
    private let startTime = Date()
    private var lastEventTime: Date?

    // MARK: - Types

    private struct SynthesisTracker {
        let startTime: Date
        let voiceId: String
        let characterCount: Int
        let sampleRate: Int
        let framework: InferenceFrameworkType
    }

    // MARK: - Initialization

    public init() {}

    // MARK: - Synthesis Tracking

    /// Start tracking a synthesis
    /// - Parameters:
    ///   - text: The text to synthesize
    ///   - voice: The voice ID being used
    ///   - sampleRate: Audio sample rate in Hz (default 22050)
    ///   - framework: The inference framework being used
    /// - Returns: A unique synthesis ID for tracking
    public func startSynthesis(
        text: String,
        voice: String,
        sampleRate: Int = 22050,
        framework: InferenceFrameworkType = .unknown
    ) -> String {
        let id = UUID().uuidString
        let characterCount = text.count

        activeSyntheses[id] = SynthesisTracker(
            startTime: Date(),
            voiceId: voice,
            characterCount: characterCount,
            sampleRate: sampleRate,
            framework: framework
        )

        EventPublisher.shared.track(TTSEvent.synthesisStarted(
            synthesisId: id,
            voiceId: voice,
            characterCount: characterCount,
            sampleRate: sampleRate,
            framework: framework
        ))

        logger.debug("Synthesis started: \(id), voice: \(voice), \(characterCount) characters")
        return id
    }

    /// Track synthesis chunk (analytics only, for streaming synthesis)
    public func trackSynthesisChunk(synthesisId: String, chunkSize: Int) {
        EventPublisher.shared.track(TTSEvent.synthesisChunk(
            synthesisId: synthesisId,
            chunkSize: chunkSize
        ))
    }

    /// Complete a synthesis
    /// - Parameters:
    ///   - synthesisId: The synthesis ID from startSynthesis
    ///   - audioDurationMs: Duration of the generated audio in milliseconds
    ///   - audioSizeBytes: Size of the generated audio in bytes
    public func completeSynthesis(
        synthesisId: String,
        audioDurationMs: Double,
        audioSizeBytes: Int
    ) {
        guard let tracker = activeSyntheses.removeValue(forKey: synthesisId) else { return }

        let endTime = Date()
        let processingTimeMs = endTime.timeIntervalSince(tracker.startTime) * 1000
        let characterCount = tracker.characterCount

        // Calculate characters per second (synthesis speed)
        let charsPerSecond = processingTimeMs > 0 ? Double(characterCount) / (processingTimeMs / 1000.0) : 0

        // Update metrics
        synthesisCount += 1
        totalCharacters += characterCount
        totalProcessingTimeMs += processingTimeMs
        totalAudioDurationMs += audioDurationMs
        totalAudioSizeBytes += Int64(audioSizeBytes)
        totalCharactersPerSecond += charsPerSecond
        lastEventTime = endTime

        EventPublisher.shared.track(TTSEvent.synthesisCompleted(
            synthesisId: synthesisId,
            voiceId: tracker.voiceId,
            characterCount: characterCount,
            audioDurationMs: audioDurationMs,
            audioSizeBytes: audioSizeBytes,
            processingDurationMs: processingTimeMs,
            charactersPerSecond: charsPerSecond,
            sampleRate: tracker.sampleRate,
            framework: tracker.framework
        ))

        logger.debug("Synthesis completed: \(synthesisId), voice: \(tracker.voiceId), audio: \(String(format: "%.1f", audioDurationMs))ms, \(audioSizeBytes) bytes")
    }

    /// Track synthesis failure
    public func trackSynthesisFailed(
        synthesisId: String,
        errorMessage: String
    ) {
        let tracker = activeSyntheses.removeValue(forKey: synthesisId)
        lastEventTime = Date()

        EventPublisher.shared.track(TTSEvent.synthesisFailed(
            synthesisId: synthesisId,
            voiceId: tracker?.voiceId ?? "unknown",
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
            averageProcessingTimeMs: synthesisCount > 0 ? totalProcessingTimeMs / Double(synthesisCount) : 0,
            averageAudioDurationMs: synthesisCount > 0 ? totalAudioDurationMs / Double(synthesisCount) : 0,
            totalCharactersProcessed: totalCharacters,
            totalAudioSizeBytes: totalAudioSizeBytes
        )
    }
}

// MARK: - TTS Metrics

public struct TTSMetrics: AnalyticsMetrics {
    public let totalEvents: Int
    public let startTime: Date
    public let lastEventTime: Date?
    public let totalSyntheses: Int

    /// Average synthesis speed (characters processed per second)
    public let averageCharactersPerSecond: Double

    /// Average processing time in milliseconds
    public let averageProcessingTimeMs: Double

    /// Average audio duration in milliseconds
    public let averageAudioDurationMs: Double

    /// Total characters processed across all syntheses
    public let totalCharactersProcessed: Int

    /// Total audio size generated in bytes
    public let totalAudioSizeBytes: Int64

    public init(
        totalEvents: Int = 0,
        startTime: Date = Date(),
        lastEventTime: Date? = nil,
        totalSyntheses: Int = 0,
        averageCharactersPerSecond: Double = 0,
        averageProcessingTimeMs: Double = 0,
        averageAudioDurationMs: Double = 0,
        totalCharactersProcessed: Int = 0,
        totalAudioSizeBytes: Int64 = 0
    ) {
        self.totalEvents = totalEvents
        self.startTime = startTime
        self.lastEventTime = lastEventTime
        self.totalSyntheses = totalSyntheses
        self.averageCharactersPerSecond = averageCharactersPerSecond
        self.averageProcessingTimeMs = averageProcessingTimeMs
        self.averageAudioDurationMs = averageAudioDurationMs
        self.totalCharactersProcessed = totalCharactersProcessed
        self.totalAudioSizeBytes = totalAudioSizeBytes
    }
}
