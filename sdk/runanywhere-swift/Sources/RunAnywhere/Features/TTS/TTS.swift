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
/// // Configure TTS with a specific voice
/// try await TTS.shared.configure(with: TTSConfiguration(voice: "en-GB"))
///
/// // Synthesize text
/// let output = try await TTS.shared.synthesize("Hello, world!")
///
/// // Using static convenience methods
/// let audio = try await TTS.synthesize("Hello, world!")
/// ```
@MainActor
public final class TTS {

    // MARK: - Shared Instance

    /// Shared singleton instance for convenient access
    public static let shared = TTS()

    // MARK: - Properties

    private var component: TTSComponent?
    private let logger = SDKLogger(category: "TTS")

    // MARK: - Initialization

    /// Initialize with default settings
    public init() {
        logger.debug("TTS initialized")
    }

    // MARK: - Public API

    /// Access the underlying component
    /// Provides low-level operations if needed
    public var underlyingComponent: TTSComponent? {
        return component
    }

    /// Whether the TTS component is ready for synthesis
    public var isReady: Bool {
        return component?.isReady ?? false
    }

    // MARK: - Configuration

    /// Configure the TTS capability with a specific configuration
    /// - Parameter configuration: The TTS configuration to use
    public func configure(with configuration: TTSConfiguration) async throws {
        logger.info("Configuring TTS with voice: \(configuration.voice)")
        let newComponent = TTSComponent(configuration: configuration)
        try await newComponent.initialize()
        self.component = newComponent
        logger.info("TTS configured successfully")
    }

    /// Configure the TTS capability with a voice ID
    /// - Parameter voice: The voice identifier to use
    public func configure(voice: String) async throws {
        let configuration = TTSConfiguration(voice: voice)
        try await configure(with: configuration)
    }

    // MARK: - Synthesis Methods

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
        guard let component = component else {
            throw RunAnywhereError.componentNotInitialized("TTS not configured. Call configure() first.")
        }
        logger.info("Starting synthesis")
        return try await component.synthesize(text, voice: voice, language: language)
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
        guard let component = component else {
            throw RunAnywhereError.componentNotInitialized("TTS not configured. Call configure() first.")
        }
        logger.info("Starting SSML synthesis")
        return try await component.synthesizeSSML(ssml, voice: voice, language: language)
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
        guard let component = component else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: RunAnywhereError.componentNotInitialized("TTS not configured. Call configure() first."))
            }
        }
        return component.streamSynthesize(text, voice: voice, language: language)
    }

    /// Get available voices
    public func getAvailableVoices() -> [String] {
        return component?.getAvailableVoices() ?? []
    }

    /// Stop current synthesis
    public func stop() {
        logger.info("Stopping synthesis")
        component?.stopSynthesis()
    }

    /// Check if currently synthesizing
    public var isSynthesizing: Bool {
        return component?.isSynthesizing ?? false
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

    // MARK: - Cleanup

    /// Cleanup resources
    public func cleanup() async throws {
        logger.info("Cleaning up TTS")
        try await component?.cleanup()
        component = nil
    }
}
