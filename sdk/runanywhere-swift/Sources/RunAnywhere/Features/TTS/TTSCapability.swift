//
//  TTSCapability.swift
//  RunAnywhere SDK
//
//  Actor-based TTS capability that owns voice lifecycle and synthesis.
//  Uses ManagedLifecycle for unified lifecycle + analytics handling.
//

import Foundation

/// Actor-based TTS capability that provides a simplified interface for text-to-speech.
/// Owns the voice lifecycle and provides thread-safe access to synthesis operations.
///
/// Uses `ManagedLifecycle` to handle voice loading/unloading with automatic analytics tracking.
public actor TTSCapability: ModelLoadableCapability {
    public typealias Configuration = TTSConfiguration

    // MARK: - State

    /// Managed lifecycle with integrated event tracking
    private let managedLifecycle: ManagedLifecycle<TTSService>

    /// Current configuration
    private var config: TTSConfiguration?

    // MARK: - Dependencies

    private let logger = SDKLogger(category: "TTSCapability")
    private let analyticsService: TTSAnalyticsService

    /// Audio playback manager for speak() API
    private let playbackManager = AudioPlaybackManager()

    // MARK: - Initialization

    public init(analyticsService: TTSAnalyticsService = TTSAnalyticsService()) {
        self.analyticsService = analyticsService
        self.managedLifecycle = ManagedLifecycle.forTTS()
    }

    // MARK: - Configuration (Capability Protocol)

    public func configure(_ config: TTSConfiguration) {
        self.config = config
        Task { await managedLifecycle.configure(config) }
    }

    // MARK: - Voice Lifecycle (ModelLoadableCapability Protocol)
    // All lifecycle operations are delegated to ManagedLifecycle which handles analytics automatically

    public var isModelLoaded: Bool {
        get async { await managedLifecycle.isLoaded }
    }

    /// Alias for voice-specific naming
    public var isVoiceLoaded: Bool {
        get async { await managedLifecycle.isLoaded }
    }

    public var currentModelId: String? {
        get async { await managedLifecycle.currentModelId }
    }

    /// Alias for voice-specific naming
    public var currentVoiceId: String? {
        get async { await managedLifecycle.currentModelId }
    }

    /// Get available voices
    public var availableVoices: [String] {
        get async {
            guard let service = await managedLifecycle.currentService else { return [] }
            return service.availableVoices
        }
    }

    /// Whether currently synthesizing
    public var isSynthesizing: Bool {
        get async {
            guard let service = await managedLifecycle.currentService else { return false }
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
        try await managedLifecycle.load(voiceId)
    }

    public func unload() async throws {
        await managedLifecycle.unload()
    }

    public func cleanup() async {
        await managedLifecycle.reset()
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
        let service = try await managedLifecycle.requireService()
        let modelId = await managedLifecycle.modelIdOrUnknown()

        logger.info("Synthesizing text with model: \(modelId)")

        // Merge options with config defaults
        let effectiveOptions = mergeOptions(options)

        // Start synthesis tracking
        let synthesisId = await analyticsService.startSynthesis(
            text: text,
            voice: effectiveOptions.voice ?? modelId,
            sampleRate: effectiveOptions.sampleRate,
            framework: service.inferenceFramework
        )

        // Perform synthesis
        let audioData: Data
        do {
            audioData = try await service.synthesize(text: text, options: effectiveOptions)
        } catch {
            logger.error("Synthesis failed: \(error)")
            await analyticsService.trackSynthesisFailed(
                synthesisId: synthesisId,
                error: error
            )
            await managedLifecycle.trackOperationError(error, operation: "synthesize")
            throw SDKError.tts(.generationFailed, "Synthesis failed: \(error.localizedDescription)", underlying: error)
        }

        // Calculate audio duration from the generated audio data
        let audioDurationSeconds = estimateAudioDuration(dataSize: audioData.count, sampleRate: effectiveOptions.sampleRate)
        let audioDurationMs = audioDurationSeconds * 1000

        // Complete synthesis tracking
        await analyticsService.completeSynthesis(
            synthesisId: synthesisId,
            audioDurationMs: audioDurationMs,
            audioSizeBytes: audioData.count
        )

        let metrics = await analyticsService.getMetrics()
        let processingTime = metrics.lastEventTime.map { $0.timeIntervalSince(metrics.startTime) } ?? 0

        logger.info("Synthesis completed in \(Int(processingTime * 1000))ms, \(audioData.count) bytes")

        let metadata = TTSSynthesisMetadata(
            voice: effectiveOptions.voice ?? modelId,
            language: effectiveOptions.language,
            processingTime: processingTime,
            characterCount: text.count
        )

        return TTSOutput(
            audioData: audioData,
            format: effectiveOptions.audioFormat,
            duration: audioDurationSeconds,
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
                guard let service = await self.managedLifecycle.currentService else {
                    continuation.finish(
                        throwing: SDKError.tts(.componentNotReady, "TTS voice not loaded")
                    )
                    return
                }

                let modelId = await self.managedLifecycle.modelIdOrUnknown()
                let effectiveOptions = self.mergeOptions(options)

                // Start synthesis tracking
                let synthesisId = await self.analyticsService.startSynthesis(
                    text: text,
                    voice: effectiveOptions.voice ?? modelId,
                    sampleRate: effectiveOptions.sampleRate,
                    framework: service.inferenceFramework
                )

                var totalBytes = 0

                do {
                    try await service.synthesizeStream(
                        text: text,
                        options: effectiveOptions,
                        onChunk: { chunk in
                            totalBytes += chunk.count
                            Task {
                                await self.analyticsService.trackSynthesisChunk(
                                    synthesisId: synthesisId,
                                    chunkSize: chunk.count
                                )
                            }
                            continuation.yield(chunk)
                        }
                    )

                    // Complete synthesis tracking
                    let audioDurationSeconds = self.estimateAudioDuration(dataSize: totalBytes, sampleRate: effectiveOptions.sampleRate)
                    let audioDurationMs = audioDurationSeconds * 1000
                    await self.analyticsService.completeSynthesis(
                        synthesisId: synthesisId,
                        audioDurationMs: audioDurationMs,
                        audioSizeBytes: totalBytes
                    )

                    continuation.finish()
                } catch {
                    await self.analyticsService.trackSynthesisFailed(
                        synthesisId: synthesisId,
                        error: error
                    )
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Stop current synthesis
    public func stop() async {
        logger.info("Stopping synthesis")
        await managedLifecycle.currentService?.stop()
    }

    // MARK: - Speak (Synthesis + Playback)

    /// Speak text aloud - synthesizes and plays audio internally.
    ///
    /// This is the simplest way to use TTS. The SDK handles all audio playback internally.
    /// Returns metadata about what was spoken for display purposes.
    ///
    /// ## Example
    /// ```swift
    /// let result = try await RunAnywhere.speak("Hello world")
    /// print("Duration: \(result.duration)s")
    /// ```
    ///
    /// - Parameters:
    ///   - text: The text to speak
    ///   - options: Synthesis options (rate, pitch, voice, etc.)
    /// - Returns: Result containing metadata about the spoken audio
    /// - Throws: Error if synthesis or playback fails
    public func speak(
        _ text: String,
        options: TTSOptions = TTSOptions()
    ) async throws -> TTSSpeakResult {
        // Synthesize the text
        let output = try await synthesize(text, options: options)

        // Play the audio if we have audio data (neural TTS)
        // System TTS plays directly through AVSpeechSynthesizer, so audioData is empty
        if !output.audioData.isEmpty {
            logger.info("Playing synthesized audio (\(output.audioData.count) bytes)")
            try await playbackManager.play(output.audioData)
            logger.info("Playback completed")
        }

        return TTSSpeakResult(from: output)
    }

    /// Whether audio is currently playing from a speak() call
    public nonisolated var isSpeaking: Bool {
        playbackManager.isPlaying
    }

    /// Stop current speech playback
    public func stopSpeaking() {
        logger.info("Stopping speech playback")
        playbackManager.stop()
    }

    // MARK: - Analytics

    /// Get current TTS analytics metrics
    public func getAnalyticsMetrics() async -> TTSMetrics {
        await analyticsService.getMetrics()
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

    private func estimateAudioDuration(dataSize: Int, sampleRate: Int = TTSConstants.defaultSampleRate) -> TimeInterval {
        let bytesPerSample = 2 // 16-bit PCM
        let samples = dataSize / bytesPerSample
        return TimeInterval(samples) / TimeInterval(sampleRate)
    }
}
