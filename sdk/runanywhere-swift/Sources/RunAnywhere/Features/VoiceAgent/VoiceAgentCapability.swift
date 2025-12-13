//
//  VoiceAgentCapability.swift
//  RunAnywhere SDK
//
//  Simplified actor-based Voice Agent capability that composes STT, LLM, TTS, and VAD
//

import Foundation

/// Actor-based Voice Agent capability that provides a full voice conversation pipeline
/// Composes STT, LLM, TTS, and VAD capabilities for end-to-end voice processing
public actor VoiceAgentCapability: CompositeCapability {

    // MARK: - State

    /// Current configuration
    private var config: VoiceAgentConfiguration?

    /// Whether the voice agent is initialized
    private var isConfigured = false

    // MARK: - Composed Capabilities

    private let llm: LLMCapability
    private let stt: STTCapability
    private let tts: TTSCapability
    private let vad: VADCapability

    // MARK: - Dependencies

    private let logger = SDKLogger(category: "VoiceAgentCapability")

    // MARK: - Initialization

    public init(
        llm: LLMCapability,
        stt: STTCapability,
        tts: TTSCapability,
        vad: VADCapability
    ) {
        self.llm = llm
        self.stt = stt
        self.tts = tts
        self.vad = vad
    }

    // MARK: - CompositeCapability Protocol

    public var isReady: Bool {
        isConfigured
    }

    public func cleanup() async {
        logger.info("Cleaning up Voice Agent")

        await llm.cleanup()
        await stt.cleanup()
        await tts.cleanup()
        await vad.cleanup()

        isConfigured = false
    }

    // MARK: - Configuration

    /// Initialize the voice agent with configuration
    /// - Parameter config: Voice agent configuration
    public func initialize(_ config: VoiceAgentConfiguration) async throws {
        logger.info("Initializing Voice Agent")

        self.config = config

        // Initialize VAD (doesn't require model loading)
        do {
            try await vad.initialize(config.vadConfig)
        } catch {
            throw CapabilityError.compositeComponentFailed(component: "VAD", error)
        }

        // Load STT model if specified
        if let sttModelId = config.sttConfig.modelId {
            logger.info("Loading STT model: \(sttModelId)")
            do {
                try await stt.loadModel(sttModelId)
            } catch {
                throw CapabilityError.compositeComponentFailed(component: "STT", error)
            }
        }

        // Load LLM model if specified
        if let llmModelId = config.llmConfig.modelId {
            logger.info("Loading LLM model: \(llmModelId)")
            do {
                try await llm.loadModel(llmModelId)
            } catch {
                throw CapabilityError.compositeComponentFailed(component: "LLM", error)
            }
        }

        // Load TTS voice
        let ttsVoice = config.ttsConfig.voice
        logger.info("Loading TTS voice: \(ttsVoice)")
        do {
            try await tts.loadVoice(ttsVoice)
        } catch {
            throw CapabilityError.compositeComponentFailed(component: "TTS", error)
        }

        self.isConfigured = true
        logger.info("Voice Agent initialized successfully")
    }

    /// Initialize with individual model IDs (convenience)
    /// - Parameters:
    ///   - sttModelId: STT model identifier
    ///   - llmModelId: LLM model identifier
    ///   - ttsVoice: TTS voice identifier
    public func initialize(
        sttModelId: String,
        llmModelId: String,
        ttsVoice: String = "com.apple.ttsbundle.siri_female_en-US_compact"
    ) async throws {
        let config = VoiceAgentConfiguration(
            vadConfig: VADConfiguration(),
            sttConfig: STTConfiguration(modelId: sttModelId),
            llmConfig: LLMConfiguration(modelId: llmModelId),
            ttsConfig: TTSConfiguration(voice: ttsVoice)
        )
        try await initialize(config)
    }

    // MARK: - Voice Processing

    /// Process a complete voice turn: audio → transcription → LLM response → synthesized speech
    /// - Parameter audioData: Audio data from user
    /// - Returns: Voice agent result with all intermediate outputs
    public func processVoiceTurn(_ audioData: Data) async throws -> VoiceAgentResult {
        guard isConfigured else {
            throw CapabilityError.notInitialized("Voice Agent")
        }

        let metrics = CapabilityMetrics(resourceId: "voice-agent")
        logger.info("Processing voice turn")

        // Step 1: Transcribe audio
        logger.debug("Step 1: Transcribing audio")
        let transcriptionOutput = try await stt.transcribe(audioData)
        let transcription = transcriptionOutput.text

        if transcription.isEmpty {
            logger.warning("Empty transcription, skipping processing")
            throw VoiceAgentError.emptyTranscription
        }

        logger.info("Transcription: \(transcription)")

        // Step 2: Generate LLM response
        logger.debug("Step 2: Generating LLM response")
        let llmResult = try await llm.generate(transcription)
        let response = llmResult.text

        logger.info("LLM Response: \(response.prefix(100))...")

        // Step 3: Synthesize speech
        logger.debug("Step 3: Synthesizing speech")
        let ttsOutput = try await tts.synthesize(response)

        logger.info("Voice turn completed in \(Int(metrics.elapsedMs))ms")

        return VoiceAgentResult(
            speechDetected: true,
            transcription: transcription,
            response: response,
            synthesizedAudio: ttsOutput.audioData
        )
    }

    /// Process audio stream for continuous conversation
    /// - Parameter audioStream: Async stream of audio data chunks
    /// - Returns: Async stream of voice agent events
    public func processStream(_ audioStream: AsyncStream<Data>) -> AsyncThrowingStream<VoiceAgentEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                guard self.isConfigured else {
                    continuation.finish(
                        throwing: CapabilityError.notInitialized("Voice Agent")
                    )
                    return
                }

                // Collect audio chunks
                var audioBuffer = Data()
                for await chunk in audioStream {
                    audioBuffer.append(chunk)
                }

                // Process the complete audio
                do {
                    // Transcribe
                    let transcription = try await self.stt.transcribe(audioBuffer)
                    continuation.yield(.transcriptionAvailable(transcription.text))

                    // Generate response
                    let llmResult = try await self.llm.generate(transcription.text)
                    continuation.yield(.responseGenerated(llmResult.text))

                    // Synthesize
                    let ttsOutput = try await self.tts.synthesize(llmResult.text)
                    continuation.yield(.audioSynthesized(ttsOutput.audioData))

                    // Yield final result
                    let result = VoiceAgentResult(
                        speechDetected: true,
                        transcription: transcription.text,
                        response: llmResult.text,
                        synthesizedAudio: ttsOutput.audioData
                    )
                    continuation.yield(.processed(result))
                    continuation.finish()
                } catch {
                    continuation.yield(.error(error))
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Individual Component Access

    /// Transcribe audio only (without LLM/TTS)
    public func transcribe(_ audioData: Data) async throws -> String {
        guard isConfigured else {
            throw CapabilityError.notInitialized("Voice Agent")
        }
        let output = try await stt.transcribe(audioData)
        return output.text
    }

    /// Generate LLM response only
    public func generateResponse(_ prompt: String) async throws -> String {
        guard isConfigured else {
            throw CapabilityError.notInitialized("Voice Agent")
        }
        let result = try await llm.generate(prompt)
        return result.text
    }

    /// Synthesize speech only
    public func synthesizeSpeech(_ text: String) async throws -> Data {
        guard isConfigured else {
            throw CapabilityError.notInitialized("Voice Agent")
        }
        let output = try await tts.synthesize(text)
        return output.audioData
    }

    /// Check if VAD detects speech
    public func detectSpeech(_ samples: [Float]) async throws -> Bool {
        let output = try await vad.detectSpeech(in: samples)
        return output.isSpeechDetected
    }
}

// MARK: - Voice Agent Error

/// Errors specific to voice agent operations
public enum VoiceAgentError: Error, LocalizedError {
    case emptyTranscription
    case pipelineInterrupted(String)

    public var errorDescription: String? {
        switch self {
        case .emptyTranscription:
            return "No speech detected in audio"
        case .pipelineInterrupted(let reason):
            return "Voice pipeline interrupted: \(reason)"
        }
    }
}
