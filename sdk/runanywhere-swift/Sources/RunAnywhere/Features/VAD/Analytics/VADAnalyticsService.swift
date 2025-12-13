//
//  VADAnalyticsService.swift
//  RunAnywhere SDK
//
//  VAD-specific analytics service following unified pattern
//

import Foundation

// MARK: - VAD Analytics Service

/// VAD analytics service using unified pattern
public actor VADAnalyticsService: AnalyticsService {

    // MARK: - Type Aliases
    public typealias Event = VADEvent
    public typealias Metrics = VADMetrics

    // MARK: - Properties

    private let queueManager: AnalyticsQueueManager
    private let logger: SDKLogger
    private var currentSession: SessionInfo?
    private var events: [VADEvent] = []

    private struct SessionInfo {
        let id: String
        let startTime: Date
    }

    private var metrics = VADMetrics()
    private var detectionCount = 0
    private var totalEnergyLevel: Float = 0
    private var speechFrames = 0
    private var silenceFrames = 0

    // MARK: - Initialization

    public init(queueManager: AnalyticsQueueManager = .shared) {
        self.queueManager = queueManager
        self.logger = SDKLogger(category: "VADAnalytics")
    }

    // MARK: - Analytics Service Protocol

    public func track(event: VADEvent) async {
        events.append(event)
        await queueManager.enqueue(event)
        await processEvent(event)
    }

    public func trackBatch(events: [VADEvent]) async {
        self.events.append(contentsOf: events)
        await queueManager.enqueueBatch(events)
        for event in events {
            await processEvent(event)
        }
    }

    public func getMetrics() async -> VADMetrics {
        return VADMetrics(
            totalEvents: events.count,
            startTime: metrics.startTime,
            lastEventTime: events.last?.timestamp,
            totalDetections: detectionCount,
            averageEnergyLevel: detectionCount > 0 ? totalEnergyLevel / Float(detectionCount) : 0,
            totalSpeechFrames: speechFrames,
            totalSilenceFrames: silenceFrames
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

    // MARK: - VAD-Specific Methods

    /// Track a speech detection event
    public func trackDetection(
        isSpeechDetected: Bool,
        energyLevel: Float,
        confidence: Float = 1.0
    ) async {
        let eventData = VADDetectionData(
            isSpeechDetected: isSpeechDetected,
            energyLevel: energyLevel,
            confidence: confidence,
            timestamp: Date().timeIntervalSince1970
        )

        let event = VADEvent(
            type: .detectionCompleted,
            sessionId: currentSession?.id,
            eventData: eventData
        )

        await track(event: event)

        // Update metrics
        detectionCount += 1
        totalEnergyLevel += energyLevel
    }

    /// Track speech activity started
    public func trackSpeechActivityStarted() async {
        let eventData = VADSpeechActivityData(
            activityType: "started",
            timestamp: Date().timeIntervalSince1970
        )
        let event = VADEvent(
            type: .speechActivityStarted,
            sessionId: currentSession?.id,
            eventData: eventData
        )
        await track(event: event)
    }

    /// Track speech activity ended
    public func trackSpeechActivityEnded(duration: Double) async {
        let eventData = VADSpeechActivityData(
            activityType: "ended",
            duration: duration,
            timestamp: Date().timeIntervalSince1970
        )
        let event = VADEvent(
            type: .speechActivityEnded,
            sessionId: currentSession?.id,
            eventData: eventData
        )
        await track(event: event)
    }

    /// Track VAD processing completion
    public func trackProcessing(
        processingTime: TimeInterval,
        audioLength: TimeInterval,
        framesProcessed: Int,
        speechFrameCount: Int,
        silenceFrameCount: Int
    ) async {
        let eventData = VADProcessingData(
            processingTimeMs: processingTime * 1000,
            audioLengthMs: audioLength * 1000,
            framesProcessed: framesProcessed,
            speechFrames: speechFrameCount,
            silenceFrames: silenceFrameCount
        )

        let event = VADEvent(
            type: .processingCompleted,
            sessionId: currentSession?.id,
            eventData: eventData
        )

        await track(event: event)

        // Update metrics
        speechFrames += speechFrameCount
        silenceFrames += silenceFrameCount
    }

    /// Track calibration started
    public func trackCalibrationStarted(currentThreshold: Float) async {
        let eventData = VADCalibrationData(
            calibrationType: "started",
            thresholdBefore: currentThreshold
        )
        let event = VADEvent(
            type: .calibrationStarted,
            sessionId: currentSession?.id,
            eventData: eventData
        )
        await track(event: event)
    }

    /// Track calibration completed
    public func trackCalibrationCompleted(
        thresholdBefore: Float,
        thresholdAfter: Float,
        samplesCollected: Int,
        duration: Double
    ) async {
        let eventData = VADCalibrationData(
            calibrationType: "completed",
            thresholdBefore: thresholdBefore,
            thresholdAfter: thresholdAfter,
            samplesCollected: samplesCollected,
            duration: duration
        )
        let event = VADEvent(
            type: .calibrationCompleted,
            sessionId: currentSession?.id,
            eventData: eventData
        )
        await track(event: event)
    }

    /// Track calibration failed
    public func trackCalibrationFailed(error: String) async {
        let eventData = VADCalibrationData(
            calibrationType: "failed"
        )
        let event = VADEvent(
            type: .calibrationFailed,
            sessionId: currentSession?.id,
            eventData: eventData
        )
        await track(event: event)
    }

    /// Track error
    public func trackError(error: Error, context: AnalyticsContext) async {
        let eventData = ErrorEventData(
            error: error.localizedDescription,
            context: context
        )
        let event = VADEvent(
            type: .error,
            sessionId: currentSession?.id,
            eventData: eventData
        )
        await track(event: event)
    }

    // MARK: - Enterprise Telemetry Methods

    /// Track VAD processing with full enterprise metrics
    /// - Parameters:
    ///   - processingTimeMs: Time taken to process audio
    ///   - audioDurationMs: Duration of audio processed
    ///   - framesProcessed: Number of frames processed
    ///   - speechFrames: Number of frames with speech detected
    ///   - silenceFrames: Number of frames with silence detected
    ///   - averageEnergyLevel: Average energy level
    ///   - threshold: Energy threshold used
    ///   - success: Whether processing was successful
    ///   - errorMessage: Error message if failed
    public func trackProcessingTelemetry(
        processingTimeMs: Double,
        audioDurationMs: Double,
        framesProcessed: Int,
        speechFrames: Int,
        silenceFrames: Int,
        averageEnergyLevel: Float,
        threshold: Float,
        success: Bool,
        errorMessage: String? = nil
    ) async {
        let deviceInfo = TelemetryDeviceInfo.current

        let eventData = VADProcessingTelemetryData(
            device: deviceInfo.device,
            osVersion: deviceInfo.osVersion,
            platform: deviceInfo.platform,
            sdkVersion: SDKConstants.version,
            processingTimeMs: processingTimeMs,
            success: success,
            errorMessage: errorMessage,
            audioDurationMs: audioDurationMs,
            framesProcessed: framesProcessed,
            speechFrames: speechFrames,
            silenceFrames: silenceFrames,
            averageEnergyLevel: averageEnergyLevel,
            threshold: threshold
        )

        let event = VADEvent(
            type: .processingCompleted,
            sessionId: currentSession?.id,
            eventData: eventData
        )

        await track(event: event)
        logger.debug("Tracked VAD processing telemetry: \(framesProcessed) frames, \(speechFrames) speech, \(silenceFrames) silence")
    }

    // MARK: - Private Methods

    private func processEvent(_ event: VADEvent) async {
        // Custom processing for VAD events if needed
        // This is called after each event is tracked
    }
}
