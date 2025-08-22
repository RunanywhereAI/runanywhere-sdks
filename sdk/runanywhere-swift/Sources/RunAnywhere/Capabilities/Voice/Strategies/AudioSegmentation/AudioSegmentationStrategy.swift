import Foundation

/// Protocol for audio segmentation strategies
/// Allows custom implementation while providing default behavior
public protocol AudioSegmentationStrategy: Sendable {
    /// Determine if the current audio buffer should be processed
    /// - Parameters:
    ///   - audioBuffer: Current accumulated audio samples
    ///   - sampleRate: Audio sample rate (typically 16000)
    ///   - silenceDuration: How long silence has been detected (seconds)
    ///   - speechDuration: Duration of current speech segment (seconds)
    /// - Returns: True if the buffer should be processed, false to continue accumulating
    func shouldProcessAudio(
        audioBuffer: [Float],
        sampleRate: Int,
        silenceDuration: TimeInterval,
        speechDuration: TimeInterval
    ) -> Bool

    /// Optional: Reset internal state when speech ends
    func reset()
}

/// Default implementation using simple time-based segmentation
public struct DefaultAudioSegmentation: AudioSegmentationStrategy {
    /// Minimum speech duration before processing (seconds)
    public let minimumSpeechDuration: TimeInterval

    /// Silence duration to consider speech ended (seconds)
    public let silenceThreshold: TimeInterval

    /// Maximum speech duration before forced processing (seconds)
    public let maximumSpeechDuration: TimeInterval

    public init(
        minimumSpeechDuration: TimeInterval = 3.0,  // Increased from 1.0 for better diarization
        silenceThreshold: TimeInterval = 1.5,       // Slightly longer for phrase completion
        maximumSpeechDuration: TimeInterval = 15.0  // Force processing after 15 seconds
    ) {
        self.minimumSpeechDuration = minimumSpeechDuration
        self.silenceThreshold = silenceThreshold
        self.maximumSpeechDuration = maximumSpeechDuration
    }

    public func shouldProcessAudio(
        audioBuffer: [Float],
        sampleRate: Int,
        silenceDuration: TimeInterval,
        speechDuration: TimeInterval
    ) -> Bool {
        // Don't process very short audio
        if speechDuration < minimumSpeechDuration {
            return false
        }

        // Process if we have sufficient silence indicating phrase end
        if silenceDuration >= silenceThreshold {
            return true
        }

        // Force processing if speech is too long
        if speechDuration >= maximumSpeechDuration {
            return true
        }

        return false
    }

    public func reset() {
        // No internal state in default implementation
    }
}

/// Smart segmentation that tries to detect complete phrases
/// Can be provided by app developers for custom behavior
public struct SmartPhraseSegmentation: AudioSegmentationStrategy {
    /// Minimum phrase length in seconds
    public let minimumPhraseLength: TimeInterval

    /// Optimal phrase length for best accuracy
    public let optimalPhraseLength: TimeInterval

    /// Extended silence for phrase boundaries
    public let phraseEndSilence: TimeInterval

    /// Brief pause threshold (for breathing/thinking)
    public let briefPauseThreshold: TimeInterval

    public init(
        minimumPhraseLength: TimeInterval = 3.0,
        optimalPhraseLength: TimeInterval = 8.0,
        phraseEndSilence: TimeInterval = 2.0,
        briefPauseThreshold: TimeInterval = 0.5
    ) {
        self.minimumPhraseLength = minimumPhraseLength
        self.optimalPhraseLength = optimalPhraseLength
        self.phraseEndSilence = phraseEndSilence
        self.briefPauseThreshold = briefPauseThreshold
    }

    public func shouldProcessAudio(
        audioBuffer: [Float],
        sampleRate: Int,
        silenceDuration: TimeInterval,
        speechDuration: TimeInterval
    ) -> Bool {
        // Never process very short segments
        if speechDuration < minimumPhraseLength {
            return false
        }

        // For optimal length, be more lenient with silence threshold
        if speechDuration >= optimalPhraseLength {
            return silenceDuration >= briefPauseThreshold * 2
        }

        // For longer segments, require extended silence for phrase boundary
        if speechDuration >= minimumPhraseLength {
            return silenceDuration >= phraseEndSilence
        }

        // Force processing for very long segments
        if speechDuration >= 15.0 {
            return true
        }

        return false
    }

    public func reset() {
        // No internal state needed
    }
}
