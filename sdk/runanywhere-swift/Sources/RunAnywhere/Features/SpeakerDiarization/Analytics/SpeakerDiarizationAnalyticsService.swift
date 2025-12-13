// swiftlint:disable file_length
//
//  SpeakerDiarizationAnalyticsService.swift
//  RunAnywhere SDK
//
//  SpeakerDiarization-specific analytics service following unified pattern
//

import Foundation

// MARK: - SpeakerDiarization Event

/// SpeakerDiarization-specific analytics event
public struct SpeakerDiarizationEvent: AnalyticsEvent {
    public let id: String
    public let type: String
    public let timestamp: Date
    public let sessionId: String?
    public let eventData: any AnalyticsEventData

    public init(
        type: SpeakerDiarizationEventType,
        sessionId: String? = nil,
        eventData: any AnalyticsEventData
    ) {
        self.id = UUID().uuidString
        self.type = type.rawValue
        self.timestamp = Date()
        self.sessionId = sessionId
        self.eventData = eventData
    }
}

/// SpeakerDiarization event types
public enum SpeakerDiarizationEventType: String {
    case diarizationStarted = "speaker_diarization_started"
    case diarizationCompleted = "speaker_diarization_completed"
    case speakerDetected = "speaker_diarization_speaker_detected"
    case speakerChanged = "speaker_diarization_speaker_changed"
    case speakerNameUpdated = "speaker_diarization_speaker_name_updated"
    case speakerProfileCreated = "speaker_diarization_profile_created"
    case audioProcessed = "speaker_diarization_audio_processed"
    case error = "speaker_diarization_error"
}

// MARK: - SpeakerDiarization Event Data Models

/// Diarization completion event data with full telemetry fields
public struct SpeakerDiarizationTelemetryData: AnalyticsEventData {
    // Model info (if applicable)
    public let modelId: String?
    public let modelName: String?
    public let framework: String?

    // Device info
    public let device: String?
    public let osVersion: String?
    public let platform: String?
    public let sdkVersion: String?

    // Common performance metrics
    public let processingTimeMs: Double?
    public let success: Bool
    public let errorMessage: String?

    // SpeakerDiarization-specific fields
    public let audioDurationMs: Double?
    public let speakerCount: Int?
    public let segmentCount: Int?
    public let averageConfidence: Double?
    public let maxSpeakers: Int?

    public init(
        modelId: String?,
        modelName: String?,
        framework: String?,
        device: String?,
        osVersion: String?,
        platform: String?,
        sdkVersion: String?,
        processingTimeMs: Double?,
        success: Bool,
        errorMessage: String? = nil,
        audioDurationMs: Double?,
        speakerCount: Int?,
        segmentCount: Int?,
        averageConfidence: Double?,
        maxSpeakers: Int?
    ) {
        self.modelId = modelId
        self.modelName = modelName
        self.framework = framework
        self.device = device
        self.osVersion = osVersion
        self.platform = platform
        self.sdkVersion = sdkVersion
        self.processingTimeMs = processingTimeMs
        self.success = success
        self.errorMessage = errorMessage
        self.audioDurationMs = audioDurationMs
        self.speakerCount = speakerCount
        self.segmentCount = segmentCount
        self.averageConfidence = averageConfidence
        self.maxSpeakers = maxSpeakers
    }
}

/// Speaker profile creation event data
public struct SpeakerProfileCreationData: AnalyticsEventData {
    public let speakerId: String
    public let timestamp: TimeInterval

    public init(speakerId: String) {
        self.speakerId = speakerId
        self.timestamp = Date().timeIntervalSince1970
    }
}

/// Speaker name update event data
public struct SpeakerNameUpdateData: AnalyticsEventData {
    public let speakerId: String
    public let oldName: String?
    public let newName: String
    public let timestamp: TimeInterval

    public init(speakerId: String, oldName: String?, newName: String) {
        self.speakerId = speakerId
        self.oldName = oldName
        self.newName = newName
        self.timestamp = Date().timeIntervalSince1970
    }
}

/// Audio processing event data
public struct AudioProcessingData: AnalyticsEventData {
    public let sampleCount: Int
    public let durationMs: Double
    public let speakerId: String
    public let confidence: Float

    public init(sampleCount: Int, durationMs: Double, speakerId: String, confidence: Float) {
        self.sampleCount = sampleCount
        self.durationMs = durationMs
        self.speakerId = speakerId
        self.confidence = confidence
    }
}

// MARK: - SpeakerDiarization Metrics

/// SpeakerDiarization-specific metrics
public struct SpeakerDiarizationMetrics: AnalyticsMetrics {
    public let totalEvents: Int
    public let startTime: Date
    public let lastEventTime: Date?
    public let totalDiarizations: Int
    public let totalSpeakersDetected: Int
    public let averageConfidence: Float
    public let averageProcessingTime: TimeInterval

    public init() {
        self.totalEvents = 0
        self.startTime = Date()
        self.lastEventTime = nil
        self.totalDiarizations = 0
        self.totalSpeakersDetected = 0
        self.averageConfidence = 0
        self.averageProcessingTime = 0
    }

    public init(
        totalEvents: Int,
        startTime: Date,
        lastEventTime: Date?,
        totalDiarizations: Int,
        totalSpeakersDetected: Int,
        averageConfidence: Float,
        averageProcessingTime: TimeInterval
    ) {
        self.totalEvents = totalEvents
        self.startTime = startTime
        self.lastEventTime = lastEventTime
        self.totalDiarizations = totalDiarizations
        self.totalSpeakersDetected = totalSpeakersDetected
        self.averageConfidence = averageConfidence
        self.averageProcessingTime = averageProcessingTime
    }
}

// MARK: - SpeakerDiarization Analytics Service

/// SpeakerDiarization analytics service using unified pattern
public actor SpeakerDiarizationAnalyticsService: AnalyticsService {

    // MARK: - Type Aliases
    public typealias Event = SpeakerDiarizationEvent
    public typealias Metrics = SpeakerDiarizationMetrics

    // MARK: - Properties

    private let queueManager: AnalyticsQueueManager
    private let logger: SDKLogger
    private var currentSession: SessionInfo?
    private var events: [SpeakerDiarizationEvent] = []

    private struct SessionInfo {
        let id: String
        let modelId: String?
        let startTime: Date
    }

    private var metrics = SpeakerDiarizationMetrics()
    private var diarizationCount = 0
    private var totalSpeakersDetected = 0
    private var totalConfidence: Float = 0
    private var totalProcessingTime: TimeInterval = 0

    // MARK: - Initialization

    public init(queueManager: AnalyticsQueueManager = .shared) {
        self.queueManager = queueManager
        self.logger = SDKLogger(category: "SpeakerDiarizationAnalytics")
    }

    // MARK: - Analytics Service Protocol

    public func track(event: SpeakerDiarizationEvent) async {
        events.append(event)
        await queueManager.enqueue(event)
        await processEvent(event)
    }

    public func trackBatch(events: [SpeakerDiarizationEvent]) async {
        self.events.append(contentsOf: events)
        await queueManager.enqueueBatch(events)
        for event in events {
            await processEvent(event)
        }
    }

    public func getMetrics() async -> SpeakerDiarizationMetrics {
        return SpeakerDiarizationMetrics(
            totalEvents: events.count,
            startTime: metrics.startTime,
            lastEventTime: events.last?.timestamp,
            totalDiarizations: diarizationCount,
            totalSpeakersDetected: totalSpeakersDetected,
            averageConfidence: diarizationCount > 0 ? totalConfidence / Float(diarizationCount) : 0,
            averageProcessingTime: diarizationCount > 0 ? totalProcessingTime / Double(diarizationCount) : 0
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

    // MARK: - SpeakerDiarization-Specific Methods

    /// Track a diarization completion
    public func trackDiarization(
        speakerCount: Int,
        confidence: Float,
        duration: TimeInterval,
        audioLength: TimeInterval
    ) async {
        let eventData = AudioProcessingData(
            sampleCount: 0, // Not tracked at this level
            durationMs: duration * 1000,
            speakerId: "multiple",
            confidence: confidence
        )

        let event = SpeakerDiarizationEvent(
            type: .diarizationCompleted,
            sessionId: currentSession?.id,
            eventData: eventData
        )

        await track(event: event)

        // Update metrics
        diarizationCount += 1
        totalSpeakersDetected += speakerCount
        totalConfidence += confidence
        totalProcessingTime += duration
    }

    /// Track speaker detection
    public func trackSpeakerDetection(speakerId: String, confidence: Float) async {
        let eventData = SpeakerDetectionData(
            speakerId: speakerId,
            confidence: confidence,
            timestamp: Date().timeIntervalSince1970
        )
        let event = SpeakerDiarizationEvent(
            type: .speakerDetected,
            sessionId: currentSession?.id,
            eventData: eventData
        )
        await track(event: event)
    }

    /// Track speaker change
    public func trackSpeakerChange(from: String?, to: String) async {
        let eventData = SpeakerChangeData(
            fromSpeaker: from,
            toSpeaker: to,
            timestamp: Date().timeIntervalSince1970
        )
        let event = SpeakerDiarizationEvent(
            type: .speakerChanged,
            sessionId: currentSession?.id,
            eventData: eventData
        )
        await track(event: event)
    }

    /// Track speaker name update
    public func trackSpeakerNameUpdate(speakerId: String, oldName: String?, newName: String) async {
        let eventData = SpeakerNameUpdateData(
            speakerId: speakerId,
            oldName: oldName,
            newName: newName
        )
        let event = SpeakerDiarizationEvent(
            type: .speakerNameUpdated,
            sessionId: currentSession?.id,
            eventData: eventData
        )
        await track(event: event)
    }

    /// Track speaker profile creation
    public func trackSpeakerProfileCreated(speakerId: String) async {
        let eventData = SpeakerProfileCreationData(speakerId: speakerId)
        let event = SpeakerDiarizationEvent(
            type: .speakerProfileCreated,
            sessionId: currentSession?.id,
            eventData: eventData
        )
        await track(event: event)
    }

    /// Track audio processing
    public func trackAudioProcessed(
        sampleCount: Int,
        duration: TimeInterval,
        speakerId: String,
        confidence: Float
    ) async {
        let eventData = AudioProcessingData(
            sampleCount: sampleCount,
            durationMs: duration * 1000,
            speakerId: speakerId,
            confidence: confidence
        )
        let event = SpeakerDiarizationEvent(
            type: .audioProcessed,
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
        let event = SpeakerDiarizationEvent(
            type: .error,
            sessionId: currentSession?.id,
            eventData: eventData
        )
        await track(event: event)
    }

    // MARK: - Enterprise Telemetry Methods

    /// Track diarization completion with full enterprise metrics
    /// - Parameters:
    ///   - modelId: Model identifier (if applicable)
    ///   - modelName: Human-readable model name
    ///   - framework: Framework used
    ///   - processingTimeMs: Time taken to process in milliseconds
    ///   - audioDurationMs: Duration of audio processed
    ///   - speakerCount: Number of speakers detected
    ///   - segmentCount: Number of segments identified
    ///   - averageConfidence: Average confidence score
    ///   - maxSpeakers: Maximum speakers configured
    ///   - success: Whether the diarization was successful
    ///   - errorMessage: Error message if failed
    public func trackDiarizationCompleted( // swiftlint:disable:this function_parameter_count
        modelId: String?,
        modelName: String?,
        framework: String?,
        processingTimeMs: Double,
        audioDurationMs: Double,
        speakerCount: Int,
        segmentCount: Int,
        averageConfidence: Double,
        maxSpeakers: Int,
        success: Bool,
        errorMessage: String? = nil
    ) async {
        let deviceInfo = TelemetryDeviceInfo.current
        let eventData = SpeakerDiarizationTelemetryData(
            modelId: modelId,
            modelName: modelName,
            framework: framework,
            device: deviceInfo.device,
            osVersion: deviceInfo.osVersion,
            platform: deviceInfo.platform,
            sdkVersion: SDKConstants.version,
            processingTimeMs: processingTimeMs,
            success: success,
            errorMessage: errorMessage,
            audioDurationMs: audioDurationMs,
            speakerCount: speakerCount,
            segmentCount: segmentCount,
            averageConfidence: averageConfidence,
            maxSpeakers: maxSpeakers
        )

        let event = SpeakerDiarizationEvent(
            type: .diarizationCompleted,
            sessionId: currentSession?.id,
            eventData: eventData
        )

        await track(event: event)

        // Also update local metrics
        if success {
            diarizationCount += 1
            totalSpeakersDetected += speakerCount
            totalConfidence += Float(averageConfidence)
            totalProcessingTime += processingTimeMs / 1000.0
        }

        // Submit to telemetry service
        let telemetryService = await ServiceContainer.shared.telemetryService
        do {
            try await telemetryService.trackSpeakerDiarizationCompleted(
                modelId: modelId,
                modelName: modelName,
                framework: framework,
                processingTimeMs: processingTimeMs,
                audioDurationMs: audioDurationMs,
                speakerCount: speakerCount,
                segmentCount: segmentCount,
                averageConfidence: averageConfidence,
                maxSpeakers: maxSpeakers,
                device: deviceInfo.device,
                osVersion: deviceInfo.osVersion,
                success: success,
                errorMessage: errorMessage
            )
            logger.debug("Tracked speaker diarization completion")
        } catch {
            logger.error("Failed to track speaker diarization completion: \(error)")
        }
    }

    // MARK: - Private Methods

    private func processEvent(_ event: SpeakerDiarizationEvent) async {
        // Custom processing for SpeakerDiarization events if needed
        // This is called after each event is tracked
    }
}
