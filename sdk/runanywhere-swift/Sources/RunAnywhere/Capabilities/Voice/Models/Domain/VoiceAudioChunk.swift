import Foundation

/// A chunk of audio data for streaming processing
public struct VoiceAudioChunk {
    /// The audio samples as Float32 array (SIMPLIFIED - no more Data conversion)
    public let samples: [Float]

    /// Timestamp when this chunk was captured
    public let timestamp: TimeInterval

    /// Sample rate of the audio (e.g., 16000 for 16kHz)
    public let sampleRate: Int

    /// Number of channels (1 for mono, 2 for stereo)
    public let channels: Int

    /// Sequence number for ordering chunks
    public let sequenceNumber: Int

    /// Whether this is the final chunk in a stream
    public let isFinal: Bool

    public init(
        samples: [Float],
        timestamp: TimeInterval,
        sampleRate: Int = 16000,
        channels: Int = 1,
        sequenceNumber: Int = 0,
        isFinal: Bool = false
    ) {
        self.samples = samples
        self.timestamp = timestamp
        self.sampleRate = sampleRate
        self.channels = channels
        self.sequenceNumber = sequenceNumber
        self.isFinal = isFinal
    }

    /// Convert Float samples to Data
    public var data: Data {
        return samples.withUnsafeBytes { bytes in
            Data(bytes)
        }
    }

    /// Duration of this audio chunk in seconds
    public var duration: TimeInterval {
        return TimeInterval(samples.count) / TimeInterval(sampleRate * channels)
    }

    /// Number of samples in this chunk
    public var sampleCount: Int {
        return samples.count / channels
    }
}
