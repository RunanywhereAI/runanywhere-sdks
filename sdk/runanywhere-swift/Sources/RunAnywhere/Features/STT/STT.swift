//
//  STT.swift
//  RunAnywhere SDK
//
//  Public entry point for the STT (Speech-to-Text) capability
//

@preconcurrency import AVFoundation
import Foundation

/// Public entry point for the STT (Speech-to-Text) capability
/// Provides simplified access to speech-to-text transcription
@MainActor
public final class STT {

    // MARK: - Shared Instance

    /// Shared singleton instance for convenient access
    public static let shared = STT()

    // MARK: - Properties

    private var component: STTComponent?
    private let logger = SDKLogger(category: "STT")

    // MARK: - Initialization

    /// Initialize with default settings
    public init() {
        logger.debug("STT initialized")
    }

    // MARK: - Public API

    /// Access the underlying component
    /// Provides low-level operations if needed
    public var underlyingComponent: STTComponent? {
        return component
    }

    /// Whether the STT component is ready for transcription
    public var isReady: Bool {
        return component?.isReady ?? false
    }

    /// Whether the underlying service supports live/streaming transcription
    public var supportsStreaming: Bool {
        return component?.supportsStreaming ?? false
    }

    /// Get the recommended transcription mode based on service capabilities
    public var recommendedMode: STTMode {
        return component?.recommendedMode ?? .batch
    }

    // MARK: - Configuration

    /// Configure the STT capability with a specific configuration
    /// - Parameter configuration: The STT configuration to use
    public func configure(with configuration: STTConfiguration) async throws {
        logger.info("Configuring STT with model: \(configuration.modelId ?? "default")")
        let newComponent = STTComponent(configuration: configuration)
        try await newComponent.initialize()
        self.component = newComponent
        logger.info("STT configured successfully")
    }

    /// Configure the STT capability with a model ID
    /// - Parameter modelId: The model identifier to use
    public func configure(modelId: String) async throws {
        let configuration = STTConfiguration(modelId: modelId)
        try await configure(with: configuration)
    }

    // MARK: - Transcription Methods

    /// Transcribe audio data in batch mode
    /// - Parameters:
    ///   - audioData: Raw audio data
    ///   - options: Transcription options
    /// - Returns: Transcription output with text, confidence, and metadata
    public func transcribe(_ audioData: Data, options: STTOptions = .default()) async throws -> STTOutput {
        guard let component = component else {
            throw RunAnywhereError.componentNotInitialized("STT not configured. Call configure() first.")
        }
        logger.info("Starting transcription")
        return try await component.transcribe(audioData, options: options)
    }

    /// Transcribe audio data with simple parameters
    /// - Parameters:
    ///   - audioData: Raw audio data
    ///   - format: Audio format
    ///   - language: Language code (optional)
    /// - Returns: Transcription output
    public func transcribe(_ audioData: Data, format: AudioFormat = .wav, language: String? = nil) async throws -> STTOutput {
        guard let component = component else {
            throw RunAnywhereError.componentNotInitialized("STT not configured. Call configure() first.")
        }
        return try await component.transcribe(audioData, format: format, language: language)
    }

    /// Transcribe audio buffer
    /// - Parameters:
    ///   - audioBuffer: Audio buffer to transcribe
    ///   - language: Language code (optional)
    /// - Returns: Transcription output
    public func transcribe(_ audioBuffer: AVAudioPCMBuffer, language: String? = nil) async throws -> STTOutput {
        guard let component = component else {
            throw RunAnywhereError.componentNotInitialized("STT not configured. Call configure() first.")
        }
        return try await component.transcribe(audioBuffer, language: language)
    }

    /// Transcribe with VAD context
    /// - Parameters:
    ///   - audioData: Raw audio data
    ///   - format: Audio format
    ///   - vadOutput: VAD output for context
    /// - Returns: Transcription output
    public func transcribeWithVAD(_ audioData: Data, format: AudioFormat = .wav, vadOutput: VADOutput) async throws -> STTOutput {
        guard let component = component else {
            throw RunAnywhereError.componentNotInitialized("STT not configured. Call configure() first.")
        }
        return try await component.transcribeWithVAD(audioData, format: format, vadOutput: vadOutput)
    }

    // MARK: - Streaming Transcription

    /// Live transcription with real-time partial results
    /// - Parameters:
    ///   - audioStream: Async sequence of audio data chunks
    ///   - options: Transcription options
    /// - Returns: Async stream of transcription text
    public func liveTranscribe<S: AsyncSequence>(
        _ audioStream: S,
        options: STTOptions = .default()
    ) throws -> AsyncThrowingStream<String, Error> where S.Element == Data {
        guard let component = component else {
            throw RunAnywhereError.componentNotInitialized("STT not configured. Call configure() first.")
        }
        return component.liveTranscribe(audioStream, options: options)
    }

    /// Stream transcription
    /// - Parameters:
    ///   - audioStream: Async sequence of audio data chunks
    ///   - language: Language code (optional)
    /// - Returns: Async stream of transcription text
    public func streamTranscribe<S: AsyncSequence>(
        _ audioStream: S,
        language: String? = nil
    ) throws -> AsyncThrowingStream<String, Error> where S.Element == Data {
        guard let component = component else {
            throw RunAnywhereError.componentNotInitialized("STT not configured. Call configure() first.")
        }
        return component.streamTranscribe(audioStream, language: language)
    }

    // MARK: - Cleanup

    /// Cleanup resources
    public func cleanup() async throws {
        logger.info("Cleaning up STT")
        try await component?.cleanup()
        component = nil
    }
}
