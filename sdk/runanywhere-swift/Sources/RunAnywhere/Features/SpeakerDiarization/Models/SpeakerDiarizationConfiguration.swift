//
//  SpeakerDiarizationConfiguration.swift
//  RunAnywhere SDK
//
//  Configuration for Speaker Diarization operations
//

import Foundation

// MARK: - Speaker Diarization Configuration

/// Configuration for Speaker Diarization component
public struct SpeakerDiarizationConfiguration: ComponentConfiguration, ComponentInitParameters, Sendable {

    // MARK: - Component Type

    /// Component type identifier
    public var componentType: SDKComponent { .speakerDiarization }

    // MARK: - Model Configuration

    /// Model ID (if using ML-based diarization)
    public let modelId: String?

    // MARK: - Diarization Parameters

    /// Maximum number of speakers to track (1-100)
    public let maxSpeakers: Int

    /// Minimum speech duration to consider (seconds)
    public let minSpeechDuration: TimeInterval

    /// Threshold for detecting speaker changes (0.0-1.0)
    public let speakerChangeThreshold: Float

    /// Enable voice identification features
    public let enableVoiceIdentification: Bool

    /// Analysis window size (seconds)
    public let windowSize: TimeInterval

    /// Step size for sliding window (seconds)
    public let stepSize: TimeInterval

    // MARK: - Initialization

    public init(
        modelId: String? = nil,
        maxSpeakers: Int = 10,
        minSpeechDuration: TimeInterval = 0.5,
        speakerChangeThreshold: Float = 0.7,
        enableVoiceIdentification: Bool = false,
        windowSize: TimeInterval = 2.0,
        stepSize: TimeInterval = 0.5
    ) {
        self.modelId = modelId
        self.maxSpeakers = maxSpeakers
        self.minSpeechDuration = minSpeechDuration
        self.speakerChangeThreshold = speakerChangeThreshold
        self.enableVoiceIdentification = enableVoiceIdentification
        self.windowSize = windowSize
        self.stepSize = stepSize
    }

    // MARK: - ComponentConfiguration

    public func validate() throws {
        guard maxSpeakers > 0 && maxSpeakers <= 100 else {
            throw SpeakerDiarizationError.invalidMaxSpeakers(value: maxSpeakers)
        }
        guard minSpeechDuration > 0 && minSpeechDuration <= 10 else {
            throw SpeakerDiarizationError.invalidConfiguration(
                reason: "Min speech duration must be between 0 and 10 seconds"
            )
        }
        guard speakerChangeThreshold >= 0 && speakerChangeThreshold <= 1.0 else {
            throw SpeakerDiarizationError.invalidThreshold(value: speakerChangeThreshold)
        }
    }
}

// MARK: - Builder Pattern

extension SpeakerDiarizationConfiguration {

    /// Create configuration with builder pattern
    public static func builder(modelId: String? = nil) -> Builder {
        Builder(modelId: modelId)
    }

    public class Builder {
        private var config: SpeakerDiarizationConfiguration

        init(modelId: String?) {
            self.config = SpeakerDiarizationConfiguration(modelId: modelId)
        }

        public func maxSpeakers(_ value: Int) -> Builder {
            config = SpeakerDiarizationConfiguration(
                modelId: config.modelId,
                maxSpeakers: value,
                minSpeechDuration: config.minSpeechDuration,
                speakerChangeThreshold: config.speakerChangeThreshold,
                enableVoiceIdentification: config.enableVoiceIdentification,
                windowSize: config.windowSize,
                stepSize: config.stepSize
            )
            return self
        }

        public func minSpeechDuration(_ value: TimeInterval) -> Builder {
            config = SpeakerDiarizationConfiguration(
                modelId: config.modelId,
                maxSpeakers: config.maxSpeakers,
                minSpeechDuration: value,
                speakerChangeThreshold: config.speakerChangeThreshold,
                enableVoiceIdentification: config.enableVoiceIdentification,
                windowSize: config.windowSize,
                stepSize: config.stepSize
            )
            return self
        }

        public func speakerChangeThreshold(_ value: Float) -> Builder {
            config = SpeakerDiarizationConfiguration(
                modelId: config.modelId,
                maxSpeakers: config.maxSpeakers,
                minSpeechDuration: config.minSpeechDuration,
                speakerChangeThreshold: value,
                enableVoiceIdentification: config.enableVoiceIdentification,
                windowSize: config.windowSize,
                stepSize: config.stepSize
            )
            return self
        }

        public func enableVoiceIdentification(_ enabled: Bool) -> Builder {
            config = SpeakerDiarizationConfiguration(
                modelId: config.modelId,
                maxSpeakers: config.maxSpeakers,
                minSpeechDuration: config.minSpeechDuration,
                speakerChangeThreshold: config.speakerChangeThreshold,
                enableVoiceIdentification: enabled,
                windowSize: config.windowSize,
                stepSize: config.stepSize
            )
            return self
        }

        public func windowSize(_ value: TimeInterval) -> Builder {
            config = SpeakerDiarizationConfiguration(
                modelId: config.modelId,
                maxSpeakers: config.maxSpeakers,
                minSpeechDuration: config.minSpeechDuration,
                speakerChangeThreshold: config.speakerChangeThreshold,
                enableVoiceIdentification: config.enableVoiceIdentification,
                windowSize: value,
                stepSize: config.stepSize
            )
            return self
        }

        public func stepSize(_ value: TimeInterval) -> Builder {
            config = SpeakerDiarizationConfiguration(
                modelId: config.modelId,
                maxSpeakers: config.maxSpeakers,
                minSpeechDuration: config.minSpeechDuration,
                speakerChangeThreshold: config.speakerChangeThreshold,
                enableVoiceIdentification: config.enableVoiceIdentification,
                windowSize: config.windowSize,
                stepSize: value
            )
            return self
        }

        public func build() -> SpeakerDiarizationConfiguration {
            config
        }
    }
}
