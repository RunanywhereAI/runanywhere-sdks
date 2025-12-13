//
//  TTSCapability.swift
//  RunAnywhere SDK
//
//  Actor-based TTS capability that owns voice lifecycle and synthesis
//

import Foundation

/// Actor-based TTS capability that provides a simplified interface for text-to-speech
/// Owns the voice lifecycle and provides thread-safe access to synthesis operations
public actor TTSCapability: ModelLoadableCapability {
    public typealias Configuration = TTSConfiguration
    public typealias Service = TTSService

    // MARK: - State

    /// Unified model lifecycle manager (uses "voice" as resource type)
    private let lifecycle: ModelLifecycleManager<TTSService>

    /// Current configuration
    private var config: TTSConfiguration?

    // MARK: - Dependencies

    private let logger = SDKLogger(category: "TTSCapability")

    // MARK: - Initialization

    public init() {
        self.lifecycle = ModelLifecycleManager.forTTS()
    }

    // MARK: - Configuration (Capability Protocol)

    public func configure(_ config: TTSConfiguration) {
        self.config = config
        Task { await lifecycle.configure(config) }
    }

    // MARK: - Voice Lifecycle (ModelLoadableCapability Protocol)
    // Note: TTS uses "voice" instead of "model" but follows same lifecycle pattern

    public var isModelLoaded: Bool {
        get async { await lifecycle.isLoaded }
    }

    /// Alias for voice-specific naming
    public var isVoiceLoaded: Bool {
        get async { await lifecycle.isLoaded }
    }

    public var currentModelId: String? {
        get async { await lifecycle.currentResourceId }
    }

    /// Alias for voice-specific naming
    public var currentVoiceId: String? {
        get async { await lifecycle.currentResourceId }
    }

    /// Get available voices
    public var availableVoices: [String] {
        get async {
            guard let service = await lifecycle.currentService else { return [] }
            return service.availableVoices
        }
    }

    /// Whether currently synthesizing
    public var isSynthesizing: Bool {
        get async {
            guard let service = await lifecycle.currentService else { return false }
            return service.isSynthesizing
        }
    }

    public func loadModel(_ modelId: String) async throws {
        try await loadVoice(modelId)
    }

    /// Load a voice by ID
    /// - Parameter voiceId: The voice identifier
    /// - Throws: Error if loading fails
    public func loadVoice(_ voiceId: String) async throws {
        try await lifecycle.load(voiceId)
    }

    public func unload() async throws {
        await lifecycle.unload()
    }

    public func cleanup() async {
        await lifecycle.reset()
    }

    // MARK: - Synthesis

    /// Synthesize text to speech
    /// - Parameters:
    ///   - text: The text to synthesize
    ///   - options: Synthesis options
    /// - Returns: TTS output with audio data
    public func synthesize(
        _ text: String,
        options: TTSOptions = TTSOptions()
    ) async throws -> TTSOutput {
        let service = try await lifecycle.requireService()
        let metrics = CapabilityMetrics(resourceId: await lifecycle.currentResourceId ?? "unknown")
        let voiceId = await lifecycle.currentResourceId ?? "unknown"

        logger.info("Synthesizing text with voice: \(voiceId)")

        // Merge options with config defaults
        let effectiveOptions = mergeOptions(options)

        // Perform synthesis
        let audioData: Data
        do {
            audioData = try await service.synthesize(text: text, options: effectiveOptions)
        } catch {
            logger.error("Synthesis failed: \(error)")
            throw CapabilityError.operationFailed("Synthesis", error)
        }

        logger.info("Synthesis completed in \(Int(metrics.elapsedMs))ms, \(audioData.count) bytes")

        let metadata = TTSSynthesisMetadata(
            voice: effectiveOptions.voice ?? voiceId,
            language: effectiveOptions.language,
            processingTime: metrics.elapsedMs / 1000.0,
            characterCount: text.count
        )

        return TTSOutput(
            audioData: audioData,
            format: effectiveOptions.audioFormat,
            duration: estimateAudioDuration(dataSize: audioData.count, sampleRate: effectiveOptions.sampleRate),
            phonemeTimestamps: nil,
            metadata: metadata
        )
    }

    /// Stream synthesis for long text
    /// - Parameters:
    ///   - text: The text to synthesize
    ///   - options: Synthesis options
    /// - Returns: Async stream of audio data chunks
    public func synthesizeStream(
        _ text: String,
        options: TTSOptions = TTSOptions()
    ) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            Task {
                guard let service = await self.lifecycle.currentService else {
                    continuation.finish(
                        throwing: CapabilityError.resourceNotLoaded("TTS voice")
                    )
                    return
                }

                let effectiveOptions = self.mergeOptions(options)

                do {
                    try await service.synthesizeStream(
                        text: text,
                        options: effectiveOptions,
                        onChunk: { chunk in
                            continuation.yield(chunk)
                        }
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Stop current synthesis
    public func stop() async {
        logger.info("Stopping synthesis")
        await lifecycle.currentService?.stop()
    }

    // MARK: - Private Methods

    private func mergeOptions(_ options: TTSOptions) -> TTSOptions {
        guard let config = config else { return options }

        return TTSOptions(
            voice: options.voice ?? config.voice,
            language: options.language,
            rate: options.rate,
            pitch: options.pitch,
            volume: options.volume,
            audioFormat: options.audioFormat,
            sampleRate: options.sampleRate
        )
    }

    private func estimateAudioDuration(dataSize: Int, sampleRate: Int = 22050) -> TimeInterval {
        let bytesPerSample = 2 // 16-bit PCM
        let samples = dataSize / bytesPerSample
        return TimeInterval(samples) / TimeInterval(sampleRate)
    }
}
