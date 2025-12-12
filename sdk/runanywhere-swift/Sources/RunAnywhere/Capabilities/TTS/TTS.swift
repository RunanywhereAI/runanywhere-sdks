//
//  TTS.swift
//  RunAnywhere SDK
//
//  Public entry point for the TTS (Text-to-Speech) capability
//

import Foundation

/// Public entry point for the TTS (Text-to-Speech) capability
///
/// Provides simplified access to text-to-speech synthesis operations.
/// This is the primary interface for TTS functionality in the SDK.
///
/// Example usage:
/// ```swift
/// // Using shared instance
/// let audio = try await TTS.shared.synthesize("Hello, world!")
///
/// // Using convenience methods
/// let output = try await TTS.synthesize("Hello, world!")
///
/// // With custom configuration
/// let config = TTSConfiguration(voice: "en-GB", speakingRate: 1.2)
/// let tts = TTS(configuration: config)
/// let audio = try await tts.synthesize("Hello from Britain!")
/// ```
public final class TTS {

    // MARK: - Shared Instance

    /// Shared singleton instance for convenient access
    public static let shared = TTS()

    // MARK: - Properties

    private let ttsService: TTSService
    private let configuration: TTSConfiguration
    private let logger = SDKLogger(category: "TTS")

    // MARK: - Initialization

    /// Initialize with default configuration
    public convenience init() {
        let configuration = TTSConfiguration()
        self.init(configuration: configuration)
    }

    /// Initialize with custom configuration
    /// - Parameter configuration: TTS configuration
    public convenience init(configuration: TTSConfiguration) {
        let service = SystemTTSService()
        self.init(configuration: configuration, service: service)
    }

    /// Initialize with custom service (for testing or customization)
    /// - Parameters:
    ///   - configuration: TTS configuration
    ///   - service: The TTS service to use
    internal init(configuration: TTSConfiguration, service: TTSService) {
        self.configuration = configuration
        self.ttsService = service
        logger.debug("TTS initialized with voice: \(configuration.voice)")
    }

    // MARK: - Public API

    /// Access the underlying TTS service
    /// Provides low-level operations if needed
    public var service: TTSService {
        return ttsService
    }

    /// Current configuration
    public var currentConfiguration: TTSConfiguration {
        return configuration
    }

    // MARK: - Convenience Methods

    /// Synthesize text to speech
    /// - Parameters:
    ///   - text: The text to synthesize
    ///   - voice: Optional voice override
    ///   - language: Optional language override
    /// - Returns: TTS output with audio data and metadata
    public func synthesize(
        _ text: String,
        voice: String? = nil,
        language: String? = nil
    ) async throws -> TTSOutput {
        logger.info("Synthesizing text: '\(text.prefix(50))...'")

        let startTime = Date()

        let options = TTSOptions(
            voice: voice ?? configuration.voice,
            language: language ?? configuration.language,
            rate: configuration.speakingRate,
            pitch: configuration.pitch,
            volume: configuration.volume,
            audioFormat: configuration.audioFormat,
            sampleRate: configuration.audioFormat == .pcm ? 16000 : 44100,
            useSSML: configuration.enableSSML
        )

        let audioData = try await ttsService.synthesize(text: text, options: options)

        let processingTime = Date().timeIntervalSince(startTime)
        let duration = estimateAudioDuration(dataSize: audioData.count, format: configuration.audioFormat)

        let metadata = TTSSynthesisMetadata(
            voice: options.voice ?? configuration.voice,
            language: options.language,
            processingTime: processingTime,
            characterCount: text.count
        )

        logger.info("Synthesis completed in \(String(format: "%.2f", processingTime))s")

        return TTSOutput(
            audioData: audioData,
            format: configuration.audioFormat,
            duration: duration,
            phonemeTimestamps: nil,
            metadata: metadata
        )
    }

    /// Synthesize SSML markup to speech
    /// - Parameters:
    ///   - ssml: The SSML markup to synthesize
    ///   - voice: Optional voice override
    ///   - language: Optional language override
    /// - Returns: TTS output with audio data and metadata
    public func synthesizeSSML(
        _ ssml: String,
        voice: String? = nil,
        language: String? = nil
    ) async throws -> TTSOutput {
        logger.info("Synthesizing SSML")

        let options = TTSOptions(
            voice: voice ?? configuration.voice,
            language: language ?? configuration.language,
            rate: configuration.speakingRate,
            pitch: configuration.pitch,
            volume: configuration.volume,
            audioFormat: configuration.audioFormat,
            sampleRate: configuration.audioFormat == .pcm ? 16000 : 44100,
            useSSML: true
        )

        let startTime = Date()
        let audioData = try await ttsService.synthesize(text: ssml, options: options)
        let processingTime = Date().timeIntervalSince(startTime)
        let duration = estimateAudioDuration(dataSize: audioData.count, format: configuration.audioFormat)

        let metadata = TTSSynthesisMetadata(
            voice: options.voice ?? configuration.voice,
            language: options.language,
            processingTime: processingTime,
            characterCount: ssml.count
        )

        return TTSOutput(
            audioData: audioData,
            format: configuration.audioFormat,
            duration: duration,
            phonemeTimestamps: nil,
            metadata: metadata
        )
    }

    /// Stream synthesis for long text
    /// - Parameters:
    ///   - text: The text to synthesize
    ///   - voice: Optional voice override
    ///   - language: Optional language override
    /// - Returns: AsyncThrowingStream of audio data chunks
    public func synthesizeStream(
        _ text: String,
        voice: String? = nil,
        language: String? = nil
    ) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let options = TTSOptions(
                        voice: voice ?? configuration.voice,
                        language: language ?? configuration.language,
                        rate: configuration.speakingRate,
                        pitch: configuration.pitch,
                        volume: configuration.volume,
                        audioFormat: configuration.audioFormat,
                        sampleRate: 16000,
                        useSSML: false
                    )

                    try await ttsService.synthesizeStream(
                        text: text,
                        options: options
                    ) { chunk in
                        continuation.yield(chunk)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Get available voices
    public func getAvailableVoices() -> [String] {
        return ttsService.availableVoices
    }

    /// Stop current synthesis
    public func stop() {
        logger.info("Stopping synthesis")
        ttsService.stop()
    }

    /// Check if currently synthesizing
    public var isSynthesizing: Bool {
        return ttsService.isSynthesizing
    }

    // MARK: - Static Convenience Methods

    /// Synthesize text using shared instance
    public static func synthesize(
        _ text: String,
        voice: String? = nil,
        language: String? = nil
    ) async throws -> TTSOutput {
        return try await shared.synthesize(text, voice: voice, language: language)
    }

    /// Get available voices using shared instance
    public static func availableVoices() -> [String] {
        return shared.getAvailableVoices()
    }

    /// Stop synthesis on shared instance
    public static func stopSynthesis() {
        shared.stop()
    }

    // MARK: - Private Helpers

    private func estimateAudioDuration(dataSize: Int, format: AudioFormat) -> TimeInterval {
        // Rough estimation based on format and typical bitrates
        let bytesPerSecond: Int
        switch format {
        case .pcm, .wav:
            bytesPerSecond = 32000 // 16-bit PCM at 16kHz
        case .mp3:
            bytesPerSecond = 16000 // 128kbps MP3
        default:
            bytesPerSecond = 32000
        }

        return TimeInterval(dataSize) / TimeInterval(bytesPerSecond)
    }
}
