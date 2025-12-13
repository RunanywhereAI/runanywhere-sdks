//
//  Voice.swift
//  RunAnywhere SDK
//
//  Public entry point for the Voice capability
//  Provides simplified access to voice agent operations
//

import Foundation

/// Public entry point for the Voice capability
/// Provides simplified access to voice agent operations combining VAD, STT, LLM, and TTS
@MainActor
public final class Voice {

    // MARK: - Shared Instance

    /// Shared singleton instance for convenient access
    public static let shared = Voice()

    // MARK: - Properties

    private var component: VoiceAgentComponent?
    private let logger = SDKLogger(category: "Voice")

    // MARK: - Initialization

    /// Initialize with default settings
    public init() {
        logger.debug("Voice initialized")
    }

    // MARK: - Public API

    /// Access the underlying component
    /// Provides low-level operations if needed
    public var underlyingComponent: VoiceAgentComponent? {
        return component
    }

    /// Whether the Voice component is ready for processing
    public var isReady: Bool {
        return component?.isReady ?? false
    }

    // MARK: - Configuration

    /// Configure the Voice capability with a specific configuration
    /// - Parameter configuration: The Voice Agent configuration to use
    public func configure(with configuration: VoiceAgentConfiguration) async throws {
        logger.info("Configuring Voice Agent")
        let newComponent = VoiceAgentComponent(configuration: configuration)
        try await newComponent.initialize()
        self.component = newComponent
        logger.info("Voice configured successfully")
    }

    /// Configure the Voice capability with individual component configurations
    /// - Parameters:
    ///   - vadConfig: VAD configuration (optional, uses default if nil)
    ///   - sttConfig: STT configuration (optional, uses default if nil)
    ///   - llmConfig: LLM configuration (optional, uses default if nil)
    ///   - ttsConfig: TTS configuration (optional, uses default if nil)
    public func configure(
        vadConfig: VADConfiguration? = nil,
        sttConfig: STTConfiguration? = nil,
        llmConfig: LLMConfiguration? = nil,
        ttsConfig: TTSConfiguration? = nil
    ) async throws {
        let configuration = VoiceAgentConfiguration(
            vadConfig: vadConfig ?? VADConfiguration(),
            sttConfig: sttConfig ?? STTConfiguration(),
            llmConfig: llmConfig ?? LLMConfiguration(),
            ttsConfig: ttsConfig ?? TTSConfiguration()
        )
        try await configure(with: configuration)
    }

    /// Configure with model IDs for convenience
    /// - Parameters:
    ///   - sttModelId: STT model identifier
    ///   - llmModelId: LLM model identifier
    public func configure(sttModelId: String? = nil, llmModelId: String? = nil) async throws {
        try await configure(
            sttConfig: STTConfiguration(modelId: sttModelId),
            llmConfig: LLMConfiguration(modelId: llmModelId)
        )
    }

    // MARK: - Voice Processing Methods

    /// Process audio through the full voice pipeline
    /// - Parameter audioData: Raw audio data
    /// - Returns: Result containing transcription, response, and synthesized audio
    public func processAudio(_ audioData: Data) async throws -> VoiceAgentResult {
        guard let component = component else {
            throw RunAnywhereError.componentNotInitialized("Voice not configured. Call configure() first.")
        }
        logger.info("Processing audio through voice pipeline")
        return try await component.processAudio(audioData)
    }

    /// Process audio stream for continuous conversation
    /// - Parameter audioStream: Async stream of audio data chunks
    /// - Returns: Async stream of voice agent events
    public func processStream(_ audioStream: AsyncStream<Data>) -> AsyncThrowingStream<VoiceAgentEvent, Error> {
        guard let component = component else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: RunAnywhereError.componentNotInitialized("Voice not configured. Call configure() first."))
            }
        }
        return component.processStream(audioStream)
    }

    // MARK: - Individual Component Access

    /// Detect voice activity in audio data
    /// - Parameter audioData: Raw audio data
    /// - Returns: Whether speech was detected
    public func detectVoiceActivity(_ audioData: Data) -> Bool {
        guard let component = component else { return true }
        return component.detectVoiceActivity(audioData)
    }

    /// Transcribe audio data
    /// - Parameter audioData: Raw audio data
    /// - Returns: Transcribed text
    public func transcribe(_ audioData: Data) async throws -> String? {
        guard let component = component else {
            throw RunAnywhereError.componentNotInitialized("Voice not configured. Call configure() first.")
        }
        return try await component.transcribe(audioData)
    }

    /// Generate response using LLM
    /// - Parameter prompt: Input prompt
    /// - Returns: Generated response
    public func generateResponse(_ prompt: String) async throws -> String? {
        guard let component = component else {
            throw RunAnywhereError.componentNotInitialized("Voice not configured. Call configure() first.")
        }
        return try await component.generateResponse(prompt)
    }

    /// Synthesize speech from text
    /// - Parameter text: Text to synthesize
    /// - Returns: Synthesized audio data
    public func synthesizeSpeech(_ text: String) async throws -> Data? {
        guard let component = component else {
            throw RunAnywhereError.componentNotInitialized("Voice not configured. Call configure() first.")
        }
        return try await component.synthesizeSpeech(text)
    }

    // MARK: - Cleanup

    /// Cleanup resources
    public func cleanup() async throws {
        logger.info("Cleaning up Voice")
        try await component?.cleanup()
        component = nil
    }
}
