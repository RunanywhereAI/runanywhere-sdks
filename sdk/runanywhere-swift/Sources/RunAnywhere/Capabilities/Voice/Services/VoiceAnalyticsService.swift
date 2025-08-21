import Foundation
import os

/// Voice-specific analytics and metrics service
public class VoiceAnalyticsService {
    private let logger = SDKLogger(category: "VoiceAnalyticsService")

    // Metrics storage
    private var transcriptionMetrics: [TranscriptionMetric] = []
    private var pipelineMetrics: [PipelineMetric] = []
    private var totalTranscriptions: Int = 0
    private var totalPipelineExecutions: Int = 0

    // Performance tracking
    private var averageTranscriptionDuration: TimeInterval = 0
    private var averagePipelineDuration: TimeInterval = 0

    // Thread safety
    private let metricsQueue = DispatchQueue(label: "com.runanywhere.voice.analytics", attributes: .concurrent)

    public init() {}

    /// Initialize the analytics service
    public func initialize() async {
        logger.info("Initializing voice analytics service")
        // Any async initialization if needed
    }

    /// Track pipeline creation
    /// - Parameter config: Pipeline configuration
    public func trackPipelineCreation(config: ModularPipelineConfig) {
        metricsQueue.async(flags: .barrier) {
            self.logger.debug("Tracking pipeline creation with components: \(config.components)")
            // Track configuration usage patterns
        }
    }

    /// Track transcription performance
    /// - Parameters:
    ///   - duration: Time taken for transcription
    ///   - wordCount: Number of words transcribed
    ///   - audioLength: Length of audio in seconds
    public func trackTranscription(
        duration: TimeInterval,
        wordCount: Int,
        audioLength: TimeInterval
    ) {
        let metric = TranscriptionMetric(
            timestamp: Date(),
            duration: duration,
            wordCount: wordCount,
            audioLength: audioLength,
            realTimeFactor: duration / audioLength
        )

        metricsQueue.async(flags: .barrier) {
            self.transcriptionMetrics.append(metric)
            self.totalTranscriptions += 1

            // Update average
            let totalDuration = self.transcriptionMetrics.reduce(0) { $0 + $1.duration }
            self.averageTranscriptionDuration = totalDuration / Double(self.transcriptionMetrics.count)

            self.logger.debug("Tracked transcription: RTF=\(metric.realTimeFactor), words=\(wordCount)")
        }
    }

    /// Track pipeline execution
    /// - Parameters:
    ///   - stages: Pipeline stages executed
    ///   - totalTime: Total execution time
    public func trackPipelineExecution(
        stages: [PipelineStage],
        totalTime: TimeInterval
    ) {
        let metric = PipelineMetric(
            timestamp: Date(),
            stages: stages,
            totalDuration: totalTime
        )

        metricsQueue.async(flags: .barrier) {
            self.pipelineMetrics.append(metric)
            self.totalPipelineExecutions += 1

            // Update average
            let totalDuration = self.pipelineMetrics.reduce(0) { $0 + $1.totalDuration }
            self.averagePipelineDuration = totalDuration / Double(self.pipelineMetrics.count)

            self.logger.debug("Tracked pipeline execution: stages=\(stages.count), time=\(totalTime)s")
        }
    }

    /// Get current metrics
    /// - Returns: Voice processing metrics
    public func getMetrics() -> VoiceMetrics {
        return metricsQueue.sync {
            VoiceMetrics(
                totalTranscriptions: totalTranscriptions,
                totalPipelineExecutions: totalPipelineExecutions,
                averageTranscriptionDuration: averageTranscriptionDuration,
                averagePipelineDuration: averagePipelineDuration,
                averageRealTimeFactor: calculateAverageRTF(),
                lastTranscriptionTime: transcriptionMetrics.last?.timestamp,
                lastPipelineTime: pipelineMetrics.last?.timestamp
            )
        }
    }

    /// Get detailed transcription metrics
    /// - Parameter limit: Maximum number of metrics to return
    /// - Returns: Recent transcription metrics
    public func getTranscriptionMetrics(limit: Int = 100) -> [TranscriptionMetric] {
        return metricsQueue.sync {
            Array(transcriptionMetrics.suffix(limit))
        }
    }

    /// Get detailed pipeline metrics
    /// - Parameter limit: Maximum number of metrics to return
    /// - Returns: Recent pipeline metrics
    public func getPipelineMetrics(limit: Int = 100) -> [PipelineMetric] {
        return metricsQueue.sync {
            Array(pipelineMetrics.suffix(limit))
        }
    }

    /// Clear old metrics
    /// - Parameter olderThan: Time interval for metric age
    public func clearOldMetrics(olderThan: TimeInterval) {
        let cutoffDate = Date().addingTimeInterval(-olderThan)

        metricsQueue.async(flags: .barrier) {
            self.transcriptionMetrics.removeAll { $0.timestamp < cutoffDate }
            self.pipelineMetrics.removeAll { $0.timestamp < cutoffDate }
            self.logger.info("Cleared metrics older than \(cutoffDate)")
        }
    }

    /// Check if the analytics service is healthy
    public func isHealthy() -> Bool {
        return true
    }

    // MARK: - Private Methods

    private func calculateAverageRTF() -> Double {
        guard !transcriptionMetrics.isEmpty else { return 0 }
        let totalRTF = transcriptionMetrics.reduce(0) { $0 + $1.realTimeFactor }
        return totalRTF / Double(transcriptionMetrics.count)
    }
}

// MARK: - Metric Types

/// Transcription performance metric
public struct TranscriptionMetric {
    public let timestamp: Date
    public let duration: TimeInterval
    public let wordCount: Int
    public let audioLength: TimeInterval
    public let realTimeFactor: Double
}

/// Pipeline execution metric
public struct PipelineMetric {
    public let timestamp: Date
    public let stages: [PipelineStage]
    public let totalDuration: TimeInterval
}

/// Voice processing metrics
public struct VoiceMetrics {
    public let totalTranscriptions: Int
    public let totalPipelineExecutions: Int
    public let averageTranscriptionDuration: TimeInterval
    public let averagePipelineDuration: TimeInterval
    public let averageRealTimeFactor: Double
    public let lastTranscriptionTime: Date?
    public let lastPipelineTime: Date?
}
