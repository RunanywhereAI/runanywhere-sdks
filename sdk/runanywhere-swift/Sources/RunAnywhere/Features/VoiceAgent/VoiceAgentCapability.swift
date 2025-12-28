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

import CRACommons
import Foundation

/// Actor-based Voice Agent capability that orchestrates STT, LLM, TTS, and VAD.
/// This is a thin wrapper over the C++ rac_voice_agent API.
public actor VoiceAgentCapability {

    // MARK: - State

    /// Handle to the C++ voice agent
    private var handle: rac_voice_agent_handle_t?

    /// Component handles
    private var llmHandle: rac_handle_t?
    private var sttHandle: rac_handle_t?
    private var ttsHandle: rac_handle_t?
    private var vadHandle: rac_handle_t?

    /// Current configuration
    private var config: VoiceAgentConfiguration?

    // MARK: - Dependencies

    private let logger = SDKLogger(category: "VoiceAgentCapability")

    // MARK: - Initialization

    public init() {}

    deinit {
        if let handle = handle {
            rac_voice_agent_destroy(handle)
        }
    }

    // MARK: - Configuration

    public func configure(_ config: VoiceAgentConfiguration) {
        self.config = config
    }

    // MARK: - Lifecycle

    public var isReady: Bool {
        get async {
            guard let handle = handle else { return false }
            var ready: rac_bool_t = RAC_FALSE
            let result = rac_voice_agent_is_ready(handle, &ready)
            return result == RAC_SUCCESS && ready == RAC_TRUE
        }
    }

    /// Initialize the voice agent with configuration
    public func initialize(_ config: VoiceAgentConfiguration) async throws {
        self.config = config

        // Create component handles if needed
        if llmHandle == nil {
            var newLLMHandle: rac_handle_t?
            rac_llm_component_create(&newLLMHandle)
            llmHandle = newLLMHandle
        }
        if sttHandle == nil {
            var newSTTHandle: rac_handle_t?
            rac_stt_component_create(&newSTTHandle)
            sttHandle = newSTTHandle
        }
        if ttsHandle == nil {
            var newTTSHandle: rac_handle_t?
            rac_tts_component_create(&newTTSHandle)
            ttsHandle = newTTSHandle
        }
        if vadHandle == nil {
            var newVADHandle: rac_handle_t?
            rac_vad_component_create(&newVADHandle)
            vadHandle = newVADHandle
        }

        // Create voice agent
        var newHandle: rac_voice_agent_handle_t?
        let createResult = rac_voice_agent_create(
            llmHandle,
            sttHandle,
            ttsHandle,
            vadHandle,
            &newHandle
        )

        guard createResult == RAC_SUCCESS, let createdHandle = newHandle else {
            throw SDKError.voiceAgent(.initializationFailed, "Failed to create voice agent: \(createResult)")
        }

        handle = createdHandle

        // Build C config
        var cConfig = rac_voice_agent_config_t()

        // VAD config
        cConfig.vad_config.sample_rate = Int32(config.vadConfig.sampleRate)
        cConfig.vad_config.frame_length = Float(config.vadConfig.frameLength)
        cConfig.vad_config.energy_threshold = Float(config.vadConfig.energyThreshold)

        // Initialize
        let result = rac_voice_agent_initialize(handle, &cConfig)
        guard result == RAC_SUCCESS else {
            throw SDKError.voiceAgent(.initializationFailed, "Voice agent initialization failed: \(result)")
        }

        logger.info("Voice agent initialized")
    }

    /// Initialize using already-loaded models
    public func initializeWithLoadedModels() async throws {
        guard let handle = handle else {
            throw SDKError.voiceAgent(.notInitialized, "Voice agent not created")
        }

        let result = rac_voice_agent_initialize_with_loaded_models(handle)
        guard result == RAC_SUCCESS else {
            throw SDKError.voiceAgent(.initializationFailed, "Failed to initialize with loaded models: \(result)")
        }

        logger.info("Voice agent initialized with loaded models")
    }

    public func cleanup() async {
        if let handle = handle {
            rac_voice_agent_cleanup(handle)
            rac_voice_agent_destroy(handle)
        }
        handle = nil

        // Clean up component handles
        if let llm = llmHandle { rac_llm_component_destroy(llm) }
        if let stt = sttHandle { rac_stt_component_destroy(stt) }
        if let tts = ttsHandle { rac_tts_component_destroy(tts) }
        if let vad = vadHandle { rac_vad_component_destroy(vad) }

        llmHandle = nil
        sttHandle = nil
        ttsHandle = nil
        vadHandle = nil
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
        let transcription: String?
        if let transcriptionPtr = cResult.transcription {
            transcription = String(cString: transcriptionPtr)
        } else {
            transcription = nil
        }
        let response: String?
        if let responsePtr = cResult.response {
            response = String(cString: responsePtr)
        } else {
            response = nil
        }

        var synthesizedAudio: Data?
        if let audioPtr = cResult.synthesized_audio, cResult.synthesized_audio_size > 0 {
            synthesizedAudio = Data(bytes: audioPtr, count: cResult.synthesized_audio_size)
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
}
