import Foundation

/// Protocol for text-to-speech services
public protocol TextToSpeechService: AnyObject {
    /// Initialize the TTS service
    func initialize() async throws

    /// Synthesize text to audio
    /// - Parameters:
    ///   - text: Text to synthesize
    ///   - options: TTS options
    /// - Returns: Synthesized audio data
    func synthesize(
        text: String,
        options: TTSOptions
    ) async throws -> Data

    /// Synthesize text and play it directly
    /// - Parameters:
    ///   - text: Text to speak
    ///   - options: TTS options
    func speak(
        text: String,
        options: TTSOptions
    ) async throws

    /// Stream synthesis for long text
    /// - Parameters:
    ///   - text: Text to synthesize
    ///   - options: TTS options
    /// - Returns: Stream of audio chunks
    func synthesizeStream(
        text: String,
        options: TTSOptions
    ) -> AsyncThrowingStream<AudioChunk, Error>

    /// Stop current speech
    func stop()

    /// Pause current speech
    func pause()

    /// Resume paused speech
    func resume()

    /// Check if currently speaking
    var isSpeaking: Bool { get }

    /// Check if currently paused
    var isPaused: Bool { get }

    /// Available voices
    var availableVoices: [VoiceInfo] { get }

    /// Current voice
    var currentVoice: VoiceInfo? { get set }

    /// Check if streaming is supported
    var supportsStreaming: Bool { get }

    /// Cleanup resources
    func cleanup() async
}

/// Options for text-to-speech synthesis
public struct TTSOptions {
    /// Voice to use for synthesis
    public let voice: String?

    /// Language for synthesis
    public let language: String

    /// Speech rate (0.0 to 2.0, 1.0 is normal)
    public let rate: Float

    /// Speech pitch (0.0 to 2.0, 1.0 is normal)
    public let pitch: Float

    /// Speech volume (0.0 to 1.0)
    public let volume: Float

    /// Audio format for output
    public let audioFormat: AudioFormat

    /// Sample rate for output audio
    public let sampleRate: Int

    /// Whether to use SSML markup
    public let useSSML: Bool

    public init(
        voice: String? = nil,
        language: String = "en-US",
        rate: Float = 1.0,
        pitch: Float = 1.0,
        volume: Float = 1.0,
        audioFormat: AudioFormat = .pcm,
        sampleRate: Int = 16000,
        useSSML: Bool = false
    ) {
        self.voice = voice
        self.language = language
        self.rate = rate
        self.pitch = pitch
        self.volume = volume
        self.audioFormat = audioFormat
        self.sampleRate = sampleRate
        self.useSSML = useSSML
    }
}

/// Information about a TTS voice
public struct VoiceInfo {
    /// Unique identifier for the voice
    public let id: String

    /// Display name of the voice
    public let name: String

    /// Language code (e.g., "en-US")
    public let language: String

    /// Gender of the voice
    public let gender: VoiceGender

    /// Age group of the voice
    public let ageGroup: VoiceAgeGroup

    /// Quality level of the voice
    public let quality: VoiceQuality

    /// Whether this is a neural voice
    public let isNeural: Bool

    /// Custom attributes
    public let attributes: [String: Any]

    public init(
        id: String,
        name: String,
        language: String,
        gender: VoiceGender = .neutral,
        ageGroup: VoiceAgeGroup = .adult,
        quality: VoiceQuality = .standard,
        isNeural: Bool = false,
        attributes: [String: Any] = [:]
    ) {
        self.id = id
        self.name = name
        self.language = language
        self.gender = gender
        self.ageGroup = ageGroup
        self.quality = quality
        self.isNeural = isNeural
        self.attributes = attributes
    }
}

/// Gender of a TTS voice
public enum VoiceGender: String, CaseIterable {
    case male
    case female
    case neutral
}

/// Age group of a TTS voice
public enum VoiceAgeGroup: String, CaseIterable {
    case child
    case teen
    case adult
    case senior
}

/// Quality level of a TTS voice
public enum VoiceQuality: String, CaseIterable {
    case low
    case standard
    case high
    case premium
}

/// Audio format for TTS output
public enum AudioFormat: String, CaseIterable {
    case pcm
    case wav
    case mp3
    case aac
    case opus
    case flac
}

// MARK: - Default implementations
public extension TextToSpeechService {
    /// Default streaming implementation
    func synthesizeStream(
        text: String,
        options: TTSOptions
    ) -> AsyncThrowingStream<AudioChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let audio = try await synthesize(text: text, options: options)
                    let chunk = AudioChunk(
                        data: audio,
                        timestamp: 0,
                        sampleRate: options.sampleRate,
                        isFinal: true
                    )
                    continuation.yield(chunk)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Default streaming support
    var supportsStreaming: Bool { false }
}
