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
    ///
    /// This method is smart about reusing already-loaded models:
    /// - If a model is already loaded with the same ID, it will be reused
    /// - If a different model is loaded, it will be replaced
    /// - If no model is loaded, the specified model will be loaded
    public func initialize(_ config: VoiceAgentConfiguration) async throws {
        logger.info("Initializing Voice Agent")

        self.config = config

        // Initialize VAD (doesn't require model loading)
        do {
            try await vad.initialize(config.vadConfig)
        } catch {
            throw CapabilityError.compositeComponentFailed(component: "VAD", error)
        }

        // Load STT model if specified and not already loaded
        if let sttModelId = config.sttConfig.modelId, !sttModelId.isEmpty {
            let currentSTTModelId = await stt.currentModelId
            let sttAlreadyLoaded = await stt.isModelLoaded

            if sttAlreadyLoaded && currentSTTModelId == sttModelId {
                logger.info("STT model already loaded: \(sttModelId) - reusing")
            } else {
                logger.info("Loading STT model: \(sttModelId)")
                do {
                    try await stt.loadModel(sttModelId)
                } catch {
                    throw CapabilityError.compositeComponentFailed(component: "STT", error)
                }
            }
        } else {
            // No STT model specified - check if one is already loaded
            let sttAlreadyLoaded = await stt.isModelLoaded
            if !sttAlreadyLoaded {
                logger.warning("No STT model specified and none loaded - STT will not work")
            } else {
                logger.info("Using already loaded STT model")
            }
        }

        // Load LLM model if specified and not already loaded
        if let llmModelId = config.llmConfig.modelId, !llmModelId.isEmpty {
            let currentLLMModelId = await llm.currentModelId
            let llmAlreadyLoaded = await llm.isModelLoaded

            if llmAlreadyLoaded && currentLLMModelId == llmModelId {
                logger.info("LLM model already loaded: \(llmModelId) - reusing")
            } else {
                logger.info("Loading LLM model: \(llmModelId)")
                do {
                    try await llm.loadModel(llmModelId)
                } catch {
                    throw CapabilityError.compositeComponentFailed(component: "LLM", error)
                }
            }
        } else {
            // No LLM model specified - check if one is already loaded
            let llmAlreadyLoaded = await llm.isModelLoaded
            if !llmAlreadyLoaded {
                logger.warning("No LLM model specified and none loaded - LLM will not work")
            } else {
                logger.info("Using already loaded LLM model")
            }
        }

        // Load TTS voice if specified and not already loaded
        let ttsVoice = config.ttsConfig.voice
        if !ttsVoice.isEmpty {
            let currentTTSVoiceId = await tts.currentVoiceId
            let ttsAlreadyLoaded = await tts.isVoiceLoaded

            if ttsAlreadyLoaded && currentTTSVoiceId == ttsVoice {
                logger.info("TTS voice already loaded: \(ttsVoice) - reusing")
            } else {
                logger.info("Loading TTS voice: \(ttsVoice)")
                do {
                    try await tts.loadVoice(ttsVoice)
                } catch {
                    throw CapabilityError.compositeComponentFailed(component: "TTS", error)
                }
            }
        } else {
            // No TTS voice specified - check if one is already loaded
            let ttsAlreadyLoaded = await tts.isVoiceLoaded
            if !ttsAlreadyLoaded {
                logger.warning("No TTS voice specified and none loaded - TTS will not work")
            } else {
                logger.info("Using already loaded TTS voice")
            }
        }

        // Verify all components are ready
        let sttReady = await stt.isModelLoaded
        let llmReady = await llm.isModelLoaded
        let ttsReady = await tts.isVoiceLoaded

        if !sttReady {
            throw CapabilityError.compositeComponentFailed(
                component: "STT",
                CapabilityError.resourceNotLoaded("STT model not loaded")
            )
        }
        if !llmReady {
            throw CapabilityError.compositeComponentFailed(
                component: "LLM",
                CapabilityError.resourceNotLoaded("LLM model not loaded")
            )
        }
        if !ttsReady {
            throw CapabilityError.compositeComponentFailed(
                component: "TTS",
                CapabilityError.resourceNotLoaded("TTS voice not loaded")
            )
        }

        self.isConfigured = true
        logger.info("Voice Agent initialized successfully - all components ready")
    }

    /// Initialize using already-loaded models (no model IDs needed)
    ///
    /// Use this when models are already loaded via the individual capability APIs
    /// (e.g., RunAnywhere.loadModel(), RunAnywhere.loadSTTModel(), RunAnywhere.loadTTSVoice())
    ///
    /// This will verify all required components are loaded and mark the voice agent as ready.
    public func initializeWithLoadedModels() async throws {
        logger.info("Initializing Voice Agent with already-loaded models")

        // Initialize VAD
        do {
            try await vad.initialize(VADConfiguration())
        } catch {
            throw CapabilityError.compositeComponentFailed(component: "VAD", error)
        }

        // Verify all components are ready
        let sttReady = await stt.isModelLoaded
        let llmReady = await llm.isModelLoaded
        let ttsReady = await tts.isVoiceLoaded

        guard sttReady else {
            throw CapabilityError.compositeComponentFailed(
                component: "STT",
                CapabilityError.resourceNotLoaded("No STT model loaded. Load one first via RunAnywhere.loadSTTModel()")
            )
        }
        guard llmReady else {
            throw CapabilityError.compositeComponentFailed(
                component: "LLM",
                CapabilityError.resourceNotLoaded("No LLM model loaded. Load one first via RunAnywhere.loadModel()")
            )
        }
        guard ttsReady else {
            throw CapabilityError.compositeComponentFailed(
                component: "TTS",
                CapabilityError.resourceNotLoaded("No TTS voice loaded. Load one first via RunAnywhere.loadTTSVoice()")
            )
        }

        self.isConfigured = true
        logger.info("Voice Agent initialized with pre-loaded models - all components ready")
    }

    /// Initialize with individual model IDs (convenience)
    /// - Parameters:
    ///   - sttModelId: STT model identifier (pass empty string to use already-loaded model)
    ///   - llmModelId: LLM model identifier (pass empty string to use already-loaded model)
    ///   - ttsVoice: TTS voice identifier (pass empty string to use already-loaded voice)
    public func initialize(
        sttModelId: String,
        llmModelId: String,
        ttsVoice: String = ""
    ) async throws {
        let config = VoiceAgentConfiguration(
            vadConfig: VADConfiguration(),
            sttConfig: STTConfiguration(modelId: sttModelId.isEmpty ? nil : sttModelId),
            llmConfig: LLMConfiguration(modelId: llmModelId.isEmpty ? nil : llmModelId),
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
