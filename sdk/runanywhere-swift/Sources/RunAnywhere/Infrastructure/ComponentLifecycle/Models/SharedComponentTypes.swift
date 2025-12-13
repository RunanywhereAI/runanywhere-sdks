import Foundation

// MARK: - Shared Types for Components
// Common types used across multiple components

/// Audio metadata
public struct AudioMetadata: Sendable {
    public let channelCount: Int
    public let bitDepth: Int?
    public let codec: String?

    public init(channelCount: Int = 1, bitDepth: Int? = nil, codec: String? = nil) {
        self.channelCount = channelCount
        self.bitDepth = bitDepth
        self.codec = codec
    }
}

/// Audio format information
public enum AudioFormat: String, Sendable {
    case wav
    case mp3
    case m4a
    case flac
    case pcm
    case opus

    public var sampleRate: Int {
        switch self {
        case .wav, .pcm, .flac:
            return 16000
        case .mp3, .m4a:
            return 44100
        case .opus:
            return 48000
        }
    }
}
