import Foundation

/// A chunk of audio data for streaming processing
public struct AudioChunk {
    /// The audio data
    public let data: Data

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
        data: Data,
        timestamp: TimeInterval,
        sampleRate: Int = 16000,
        channels: Int = 1,
        sequenceNumber: Int = 0,
        isFinal: Bool = false
    ) {
        self.data = data
        self.timestamp = timestamp
        self.sampleRate = sampleRate
        self.channels = channels
        self.sequenceNumber = sequenceNumber
        self.isFinal = isFinal
    }

    /// Duration of this audio chunk in seconds
    public var duration: TimeInterval {
        let bytesPerSample = 2 // Assuming 16-bit audio
        let samples = data.count / (bytesPerSample * channels)
        return TimeInterval(samples) / TimeInterval(sampleRate)
    }

    /// Number of samples in this chunk
    public var sampleCount: Int {
        let bytesPerSample = 2 // Assuming 16-bit audio
        return data.count / (bytesPerSample * channels)
    }
}
