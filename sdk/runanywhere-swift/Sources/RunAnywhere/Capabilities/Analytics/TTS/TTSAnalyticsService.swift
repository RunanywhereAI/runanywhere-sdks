//
//  TTSAnalyticsService.swift
//  RunAnywhere SDK
//
//  TTS-specific analytics service with enterprise telemetry support
//

import Foundation

// MARK: - TTS Event

/// TTS-specific analytics event
public struct TTSEvent: AnalyticsEvent {
    public let id: String
    public let type: String
    public let timestamp: Date
    public let sessionId: String?
    public let eventData: any AnalyticsEventData

    public init(
        type: TTSEventType,
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

/// TTS event types
public enum TTSEventType: String {
    case synthesisStarted = "tts_synthesis_started"
    case synthesisCompleted = "tts_synthesis_completed"
    case synthesisChunk = "tts_synthesis_chunk"
    case modelLoaded = "tts_model_loaded"
    case modelLoadFailed = "tts_model_load_failed"
    case error = "tts_error"
}

// MARK: - TTS Event Data Models

/// TTS synthesis start event data
public struct TTSSynthesisStartData: AnalyticsEventData {
    public let characterCount: Int
    public let voice: String
    public let language: String
    public let startTimestamp: TimeInterval

    public init(characterCount: Int, voice: String, language: String) {
        self.characterCount = characterCount
        self.voice = voice
        self.language = language
        self.startTimestamp = Date().timeIntervalSince1970
    }
}

/// Parameters for TTS synthesis completion tracking
public struct TTSSynthesisCompletionParams {
    public let synthesisId: String
    public let modelId: String
    public let modelName: String
    public let framework: LLMFramework
    public let language: String
    public let characterCount: Int
    public let audioDurationMs: Double
    public let audioSizeBytes: Int
    public let sampleRate: Int
    public let processingTimeMs: Double

    public init(
        synthesisId: String,
        modelId: String,
        modelName: String,
        framework: LLMFramework,
        language: String,
        characterCount: Int,
        audioDurationMs: Double,
        audioSizeBytes: Int,
        sampleRate: Int,
        processingTimeMs: Double
    ) {
        self.synthesisId = synthesisId
        self.modelId = modelId
        self.modelName = modelName
        self.framework = framework
        self.language = language
        self.characterCount = characterCount
        self.audioDurationMs = audioDurationMs
        self.audioSizeBytes = audioSizeBytes
        self.sampleRate = sampleRate
        self.processingTimeMs = processingTimeMs
    }
}

/// TTS synthesis completion event data
public struct TTSSynthesisCompletionData: AnalyticsEventData {
    public let characterCount: Int
    public let audioDurationMs: Double
    public let audioSizeBytes: Int
    public let processingTimeMs: Double
    public let charactersPerSecond: Double
    public let realTimeFactor: Double

    public init(
        characterCount: Int,
        audioDurationMs: Double,
        audioSizeBytes: Int,
        processingTimeMs: Double
    ) {
        self.characterCount = characterCount
        self.audioDurationMs = audioDurationMs
        self.audioSizeBytes = audioSizeBytes
        self.processingTimeMs = processingTimeMs
        self.charactersPerSecond = processingTimeMs > 0 ? Double(characterCount) / (processingTimeMs / 1000.0) : 0
        self.realTimeFactor = audioDurationMs > 0 ? processingTimeMs / audioDurationMs : 0
    }
}

// MARK: - TTS Metrics

/// TTS-specific metrics
public struct TTSMetrics: AnalyticsMetrics {
    public let totalEvents: Int
    public let startTime: Date
    public let lastEventTime: Date?
    public let totalSyntheses: Int
    public let averageCharactersPerSecond: Double
    public let averageProcessingTimeMs: Double
    public let totalCharactersProcessed: Int

    public init() {
        self.totalEvents = 0
        self.startTime = Date()
        self.lastEventTime = nil
        self.totalSyntheses = 0
        self.averageCharactersPerSecond = 0
        self.averageProcessingTimeMs = 0
        self.totalCharactersProcessed = 0
    }

    public init(
        totalEvents: Int,
        startTime: Date,
        lastEventTime: Date?,
        totalSyntheses: Int,
        averageCharactersPerSecond: Double,
        averageProcessingTimeMs: Double,
        totalCharactersProcessed: Int
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

    /// Track synthesis start (local analytics)
    public func trackSynthesisStarted(text: String, voice: String, language: String) async {
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
    }

    /// Track synthesis completion (local analytics)
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

    /// Track error (local analytics)
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

    // MARK: - Enterprise Telemetry Methods
    //
    // These methods send rich telemetry data directly to TelemetryService
    // for enterprise customers who need detailed performance analytics.

    /// Track TTS model load with full enterprise metrics
    /// - Parameters:
    ///   - modelId: Unique model identifier
    ///   - modelName: Human-readable model name
    ///   - framework: Framework used (e.g., ONNX, AVSpeechSynthesizer)
    ///   - loadTimeMs: Time taken to load the model in milliseconds
    ///   - modelSizeBytes: Optional size of the model in bytes
    ///   - success: Whether the load was successful
    ///   - errorMessage: Error message if load failed
    public func trackModelLoad(
        modelId: String,
        modelName: String,
        framework: LLMFramework,
        loadTimeMs: Double,
        modelSizeBytes: Int64? = nil,
        success: Bool,
        errorMessage: String? = nil
    ) async {
        logger.info("📊 trackModelLoad called - modelId: \(modelId), modelName: \(modelName)")
        let deviceInfo = TelemetryDeviceInfo.current
        let telemetryService = await ServiceContainer.shared.telemetryService

        do {
            try await telemetryService.trackTTSModelLoad(
                modelId: modelId,
                modelName: modelName,
                framework: framework.rawValue,
                loadTimeMs: loadTimeMs,
                modelSizeBytes: modelSizeBytes,
                device: deviceInfo.device,
                osVersion: deviceInfo.osVersion,
                success: success,
                errorMessage: errorMessage
            )
            logger.info("✅ Tracked TTS model load: \(modelName)")
        } catch {
            logger.error("❌ Failed to track TTS model load: \(error)")
        }
    }

    /// Track TTS synthesis start with full enterprise metrics
    /// - Parameters:
    ///   - synthesisId: Unique synthesis session identifier
    ///   - modelId: Model being used
    ///   - modelName: Human-readable model name
    ///   - framework: Framework used
    ///   - language: Target language for synthesis
    ///   - voice: Voice identifier being used
    ///   - characterCount: Number of characters to synthesize
    ///   - speakingRate: Speaking rate multiplier
    ///   - pitch: Pitch multiplier
    public func trackSynthesisStarted( // swiftlint:disable:this function_parameter_count
        synthesisId: String,
        modelId: String,
        modelName: String,
        framework: LLMFramework,
        language: String,
        voice: String,
        characterCount: Int,
        speakingRate: Float = 1.0,
        pitch: Float = 1.0
    ) async {
        logger.info("📊 trackSynthesisStarted called - synthesisId: \(synthesisId)")
        let deviceInfo = TelemetryDeviceInfo.current
        let telemetryService = await ServiceContainer.shared.telemetryService

        do {
            try await telemetryService.trackTTSSynthesisStarted(
                synthesisId: synthesisId,
                modelId: modelId,
                modelName: modelName,
                framework: framework.rawValue,
                language: language,
                voice: voice,
                characterCount: characterCount,
                speakingRate: speakingRate,
                pitch: pitch,
                device: deviceInfo.device,
                osVersion: deviceInfo.osVersion
            )
            logger.info("✅ Tracked TTS synthesis started: \(synthesisId)")
        } catch {
            logger.error("❌ Failed to track TTS synthesis started: \(error)")
        }
    }

    /// Track TTS synthesis completion with full enterprise metrics
    /// - Parameter params: Synthesis completion parameters
    public func trackSynthesisCompleted(params: TTSSynthesisCompletionParams) async {
        logger.info("📊 trackSynthesisCompleted called - synthesisId: \(params.synthesisId)")
        let deviceInfo = TelemetryDeviceInfo.current
        let telemetryService = await ServiceContainer.shared.telemetryService

        // Calculate performance metrics
        let charactersPerSecond = params.processingTimeMs > 0 ?
            Double(params.characterCount) / (params.processingTimeMs / 1000.0) : 0
        let realTimeFactor = params.audioDurationMs > 0 ?
            params.processingTimeMs / params.audioDurationMs : 0

        do {
            try await telemetryService.trackTTSSynthesisCompleted(
                synthesisId: params.synthesisId,
                modelId: params.modelId,
                modelName: params.modelName,
                framework: params.framework.rawValue,
                language: params.language,
                characterCount: params.characterCount,
                audioDurationMs: params.audioDurationMs,
                audioSizeBytes: params.audioSizeBytes,
                sampleRate: params.sampleRate,
                processingTimeMs: params.processingTimeMs,
                charactersPerSecond: charactersPerSecond,
                realTimeFactor: realTimeFactor,
                device: deviceInfo.device,
                osVersion: deviceInfo.osVersion
            )
            logger.info(
                "✅ Tracked TTS synthesis completed: \(params.synthesisId), " +
                "CPS: \(String(format: "%.1f", charactersPerSecond))"
            )
        } catch {
            logger.error("❌ Failed to track TTS synthesis completed: \(error)")
        }

        // Update local metrics
        synthesisCount += 1
        totalCharacters += params.characterCount
        totalProcessingTime += params.processingTimeMs
        totalCharactersPerSecond += charactersPerSecond
    }

    /// Track TTS synthesis failure with full enterprise metrics
    /// - Parameters:
    ///   - synthesisId: Unique synthesis session identifier
    ///   - modelId: Model used
    ///   - modelName: Human-readable model name
    ///   - framework: Framework used
    ///   - language: Target language
    ///   - characterCount: Number of characters that were being synthesized
    ///   - processingTimeMs: Time spent before failure
    ///   - errorMessage: Description of the error
    public func trackSynthesisFailed( // swiftlint:disable:this function_parameter_count
        synthesisId: String,
        modelId: String,
        modelName: String,
        framework: LLMFramework,
        language: String,
        characterCount: Int,
        processingTimeMs: Double,
        errorMessage: String
    ) async {
        let deviceInfo = TelemetryDeviceInfo.current
        let telemetryService = await ServiceContainer.shared.telemetryService

        do {
            try await telemetryService.trackTTSSynthesisFailed(
                synthesisId: synthesisId,
                modelId: modelId,
                modelName: modelName,
                framework: framework.rawValue,
                language: language,
                characterCount: characterCount,
                processingTimeMs: processingTimeMs,
                errorMessage: errorMessage,
                device: deviceInfo.device,
                osVersion: deviceInfo.osVersion
            )
            logger.debug("Tracked TTS synthesis failed: \(synthesisId)")
        } catch {
            logger.error("Failed to track TTS synthesis failed: \(error)")
        }
    }

    // MARK: - Private Methods

    private func processEvent(_ event: TTSEvent) async {
        // Custom processing for TTS events if needed
        // This is called after each event is tracked
    }
}
