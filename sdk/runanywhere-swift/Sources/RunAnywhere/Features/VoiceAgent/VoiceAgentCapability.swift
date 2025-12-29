//
//  VoiceAgentCapability.swift
//  RunAnywhere SDK
//
//  Thin Swift wrapper over rac_voice_agent_* C API.
//  All business logic is in the C++ layer; this is just a Swift interface.
//
//  ⚠️ WARNING: This is a direct wrapper. Do NOT add custom logic here.
//  The C++ layer (runanywhere-commons) is the source of truth.
//
//  Architecture:
//  - Voice agent uses SHARED handles from the individual capabilities (STT, LLM, TTS, VAD)
//  - Models are loaded via the individual capabilities, not the voice agent
//  - Voice agent is purely an orchestrator - it doesn't own the component handles
//

import CRACommons
import Foundation

/// Actor-based Voice Agent capability that orchestrates STT, LLM, TTS, and VAD.
/// This is a thin wrapper over the C++ rac_voice_agent API.
///
/// The voice agent uses shared handles from the individual capabilities.
/// Models are loaded via STTCapability, LLMCapability, TTSCapability - not via this class.
public actor VoiceAgentCapability {

    // MARK: - State

    /// Handle to the C++ voice agent (uses shared component handles)
    private var handle: rac_voice_agent_handle_t?

    // MARK: - Dependencies

    private let logger = SDKLogger(category: "VoiceAgentCapability")

    /// References to individual capabilities (for shared handles)
    private let sttCapability: STTCapability
    private let llmCapability: LLMCapability
    private let ttsCapability: TTSCapability
    private let vadCapability: VADCapability

    // MARK: - Initialization

    public init(
        sttCapability: STTCapability,
        llmCapability: LLMCapability,
        ttsCapability: TTSCapability,
        vadCapability: VADCapability
    ) {
        self.sttCapability = sttCapability
        self.llmCapability = llmCapability
        self.ttsCapability = ttsCapability
        self.vadCapability = vadCapability
    }

    deinit {
        if let handle = handle {
            rac_voice_agent_destroy(handle)
        }
    }

    // MARK: - Lifecycle

    /// Whether the voice agent is ready (all models loaded and handle created)
    public var isReady: Bool {
        get async {
            guard let handle = handle else { return false }
            var ready: rac_bool_t = RAC_FALSE
            let result = rac_voice_agent_is_ready(handle, &ready)
            return result == RAC_SUCCESS && ready == RAC_TRUE
        }
    }

    /// Whether STT model is loaded (delegates to STTCapability)
    public var isSTTLoaded: Bool {
        get async {
            await sttCapability.isModelLoaded
        }
    }

    /// Whether LLM model is loaded (delegates to LLMCapability)
    public var isLLMLoaded: Bool {
        get async {
            await llmCapability.isModelLoaded
        }
    }

    /// Whether TTS voice is loaded (delegates to TTSCapability)
    public var isTTSLoaded: Bool {
        get async {
            await ttsCapability.isModelLoaded
        }
    }

    /// Get the currently loaded STT model ID (delegates to STTCapability)
    public var currentSTTModelId: String? {
        get async {
            await sttCapability.currentModelId
        }
    }

    /// Get the currently loaded LLM model ID (delegates to LLMCapability)
    public var currentLLMModelId: String? {
        get async {
            await llmCapability.currentModelId
        }
    }

    /// Get the currently loaded TTS voice ID (delegates to TTSCapability)
    public var currentTTSVoiceId: String? {
        get async {
            await ttsCapability.currentModelId
        }
    }

    // MARK: - Creation

    /// Create the voice agent with shared handles from individual capabilities
    public func create() async throws {
        guard handle == nil else {
            logger.debug("Voice agent already created")
            return
        }

        // Get or create handles from individual capabilities
        let llmHandle = try await llmCapability.getOrCreateHandle()
        let sttHandle = try await sttCapability.getOrCreateHandle()
        let ttsHandle = try await ttsCapability.getOrCreateHandle()
        let vadHandle = try await vadCapability.getOrCreateHandle()

        var newHandle: rac_voice_agent_handle_t?
        let result = rac_voice_agent_create(
            llmHandle,
            sttHandle,
            ttsHandle,
            vadHandle,
            &newHandle
        )

        guard result == RAC_SUCCESS, let createdHandle = newHandle else {
            throw SDKError.voiceAgent(.initializationFailed, "Failed to create voice agent: \(result)")
        }

        handle = createdHandle
        logger.info("Voice agent created with shared handles")
    }

    // MARK: - Initialization

    /// Initialize the voice agent with configuration
    public func initialize(_ config: VoiceAgentConfiguration) async throws {
        try await ensureCreated()
        guard let handle = handle else { return }

        // Build C config
        var cConfig = rac_voice_agent_config_t()

        // VAD config
        cConfig.vad_config.sample_rate = Int32(config.vadConfig.sampleRate)
        cConfig.vad_config.frame_length = Float(config.vadConfig.frameLength)
        cConfig.vad_config.energy_threshold = Float(config.vadConfig.energyThreshold)

        // STT config
        if let sttModelId = config.sttConfig.modelId {
            cConfig.stt_config.model_id = (sttModelId as NSString).utf8String
        }

        // LLM config
        if let llmModelId = config.llmConfig.modelId {
            cConfig.llm_config.model_id = (llmModelId as NSString).utf8String
        }

        // TTS config (voice is non-optional with default value)
        cConfig.tts_config.voice = (config.ttsConfig.voice as NSString).utf8String

        let result = rac_voice_agent_initialize(handle, &cConfig)
        guard result == RAC_SUCCESS else {
            throw SDKError.voiceAgent(.initializationFailed, "Voice agent initialization failed: \(result)")
        }

        logger.info("Voice agent initialized")
    }

    /// Initialize using already-loaded models from individual capabilities
    ///
    /// Use this when models were loaded via STTCapability, LLMCapability, TTSCapability.
    public func initializeWithLoadedModels() async throws {
        try await ensureCreated()
        guard let handle = handle else { return }

        let result = rac_voice_agent_initialize_with_loaded_models(handle)
        guard result == RAC_SUCCESS else {
            throw SDKError.voiceAgent(.initializationFailed, "Failed to initialize with loaded models: \(result)")
        }

        logger.info("Voice agent initialized with loaded models")
    }

    /// Cleanup voice agent resources
    public func cleanup() async {
        if let handle = handle {
            rac_voice_agent_cleanup(handle)
            rac_voice_agent_destroy(handle)
        }
        handle = nil
        logger.info("Voice agent cleaned up")
    }

    // MARK: - Voice Processing

    /// Process a complete voice turn: audio → transcription → LLM response → synthesized speech
    public func processVoiceTurn(_ audioData: Data) async throws -> VoiceAgentResult {
        guard let handle = handle else {
            throw SDKError.voiceAgent(.notInitialized, "Voice agent not initialized")
        }

        var isReady: rac_bool_t = RAC_FALSE
        rac_voice_agent_is_ready(handle, &isReady)
        guard isReady == RAC_TRUE else {
            throw SDKError.voiceAgent(.notInitialized, "Voice agent not ready")
        }

        logger.info("Processing voice turn")

        var cResult = rac_voice_agent_result_t()
        let result = audioData.withUnsafeBytes { audioPtr in
            rac_voice_agent_process_voice_turn(
                handle,
                audioPtr.baseAddress,
                audioData.count,
                &cResult
            )
        }

        guard result == RAC_SUCCESS else {
            throw SDKError.voiceAgent(.processingFailed, "Voice turn processing failed: \(result)")
        }

        // Extract results
        let speechDetected = cResult.speech_detected == RAC_TRUE
        let transcription: String? = cResult.transcription.map { String(cString: $0) }
        let response: String? = cResult.response.map { String(cString: $0) }

        // C++ now returns WAV format directly - no conversion needed
        var synthesizedAudio: Data?
        if let audioPtr = cResult.synthesized_audio, cResult.synthesized_audio_size > 0 {
            synthesizedAudio = Data(bytes: audioPtr, count: cResult.synthesized_audio_size)
            logger.info("Received \(cResult.synthesized_audio_size) bytes WAV audio")
        }

        // Free C result
        rac_voice_agent_result_free(&cResult)

        logger.info("Voice turn completed")

        return VoiceAgentResult(
            speechDetected: speechDetected,
            transcription: transcription,
            response: response,
            synthesizedAudio: synthesizedAudio
        )
    }

    // MARK: - Individual Component Access

    /// Transcribe audio only (without LLM/TTS)
    public func transcribe(_ audioData: Data) async throws -> String {
        guard let handle = handle else {
            throw SDKError.voiceAgent(.notInitialized, "Voice agent not initialized")
        }

        var transcriptionPtr: UnsafeMutablePointer<CChar>?
        let result = audioData.withUnsafeBytes { audioPtr in
            rac_voice_agent_transcribe(
                handle,
                audioPtr.baseAddress,
                audioData.count,
                &transcriptionPtr
            )
        }

        guard result == RAC_SUCCESS, let ptr = transcriptionPtr else {
            throw SDKError.voiceAgent(.processingFailed, "Transcription failed: \(result)")
        }

        let transcription = String(cString: ptr)
        free(ptr)

        return transcription
    }

    /// Generate LLM response only
    public func generateResponse(_ prompt: String) async throws -> String {
        guard let handle = handle else {
            throw SDKError.voiceAgent(.notInitialized, "Voice agent not initialized")
        }

        var responsePtr: UnsafeMutablePointer<CChar>?
        let result = prompt.withCString { promptPtr in
            rac_voice_agent_generate_response(handle, promptPtr, &responsePtr)
        }

        guard result == RAC_SUCCESS, let ptr = responsePtr else {
            throw SDKError.voiceAgent(.processingFailed, "Response generation failed: \(result)")
        }

        let response = String(cString: ptr)
        free(ptr)

        return response
    }

    /// Synthesize speech only
    public func synthesizeSpeech(_ text: String) async throws -> Data {
        guard let handle = handle else {
            throw SDKError.voiceAgent(.notInitialized, "Voice agent not initialized")
        }

        var audioPtr: UnsafeMutableRawPointer?
        var audioSize: Int = 0
        let result = text.withCString { textPtr in
            rac_voice_agent_synthesize_speech(handle, textPtr, &audioPtr, &audioSize)
        }

        guard result == RAC_SUCCESS, let ptr = audioPtr, audioSize > 0 else {
            throw SDKError.voiceAgent(.processingFailed, "Speech synthesis failed: \(result)")
        }

        let audioData = Data(bytes: ptr, count: audioSize)
        free(ptr)

        return audioData
    }

    /// Check if VAD detects speech
    public func detectSpeech(_ samples: [Float]) async throws -> Bool {
        guard let handle = handle else {
            throw SDKError.voiceAgent(.notInitialized, "Voice agent not initialized")
        }

        var detected: rac_bool_t = RAC_FALSE
        let result = samples.withUnsafeBufferPointer { buffer in
            rac_voice_agent_detect_speech(
                handle,
                buffer.baseAddress,
                buffer.count,
                &detected
            )
        }

        guard result == RAC_SUCCESS else {
            throw SDKError.voiceAgent(.processingFailed, "Speech detection failed: \(result)")
        }

        return detected == RAC_TRUE
    }

    // MARK: - Private Helpers

    private func ensureCreated() async throws {
        if handle == nil {
            try await create()
        }
    }
}
