//
//  VADEventData.swift
//  RunAnywhere SDK
//
//  VAD-specific event data models for analytics
//

import Foundation

// MARK: - VAD Event Data Models

/// VAD detection event data
public struct VADDetectionData: AnalyticsEventData {
    public let isSpeechDetected: Bool
    public let energyLevel: Float
    public let confidence: Float
    public let timestamp: TimeInterval

    public init(isSpeechDetected: Bool, energyLevel: Float, confidence: Float = 1.0, timestamp: TimeInterval) {
        self.isSpeechDetected = isSpeechDetected
        self.energyLevel = energyLevel
        self.confidence = confidence
        self.timestamp = timestamp
    }
}

/// VAD speech activity event data
public struct VADSpeechActivityData: AnalyticsEventData {
    public let activityType: String  // "started" or "ended"
    public let duration: Double?     // Duration in ms (for ended events)
    public let timestamp: TimeInterval

    public init(activityType: String, duration: Double? = nil, timestamp: TimeInterval) {
        self.activityType = activityType
        self.duration = duration
        self.timestamp = timestamp
    }
}

/// VAD processing event data
public struct VADProcessingData: AnalyticsEventData {
    public let processingTimeMs: Double
    public let audioLengthMs: Double
    public let framesProcessed: Int
    public let speechFrames: Int
    public let silenceFrames: Int

    public init(processingTimeMs: Double, audioLengthMs: Double, framesProcessed: Int, speechFrames: Int, silenceFrames: Int) {
        self.processingTimeMs = processingTimeMs
        self.audioLengthMs = audioLengthMs
        self.framesProcessed = framesProcessed
        self.speechFrames = speechFrames
        self.silenceFrames = silenceFrames
    }
}

/// VAD calibration event data
public struct VADCalibrationData: AnalyticsEventData {
    public let calibrationType: String  // "started", "completed", "failed"
    public let thresholdBefore: Float?
    public let thresholdAfter: Float?
    public let samplesCollected: Int?
    public let duration: Double?

    public init(calibrationType: String, thresholdBefore: Float? = nil, thresholdAfter: Float? = nil, samplesCollected: Int? = nil, duration: Double? = nil) {
        self.calibrationType = calibrationType
        self.thresholdBefore = thresholdBefore
        self.thresholdAfter = thresholdAfter
        self.samplesCollected = samplesCollected
        self.duration = duration
    }
}

/// VAD telemetry data for enterprise analytics
public struct VADProcessingTelemetryData: AnalyticsEventData {
    // Device info
    public let device: String?
    public let osVersion: String?
    public let platform: String?
    public let sdkVersion: String?

    // Performance metrics
    public let processingTimeMs: Double?
    public let success: Bool
    public let errorMessage: String?

    // VAD-specific fields
    public let audioDurationMs: Double?
    public let framesProcessed: Int?
    public let speechFrames: Int?
    public let silenceFrames: Int?
    public let averageEnergyLevel: Float?
    public let threshold: Float?

    public init(
        device: String?,
        osVersion: String?,
        platform: String?,
        sdkVersion: String?,
        processingTimeMs: Double?,
        success: Bool,
        errorMessage: String? = nil,
        audioDurationMs: Double? = nil,
        framesProcessed: Int? = nil,
        speechFrames: Int? = nil,
        silenceFrames: Int? = nil,
        averageEnergyLevel: Float? = nil,
        threshold: Float? = nil
    ) {
        self.device = device
        self.osVersion = osVersion
        self.platform = platform
        self.sdkVersion = sdkVersion
        self.processingTimeMs = processingTimeMs
        self.success = success
        self.errorMessage = errorMessage
        self.audioDurationMs = audioDurationMs
        self.framesProcessed = framesProcessed
        self.speechFrames = speechFrames
        self.silenceFrames = silenceFrames
        self.averageEnergyLevel = averageEnergyLevel
        self.threshold = threshold
    }
}
