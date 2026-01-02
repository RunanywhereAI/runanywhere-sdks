//
//  RunAnywhere+VoiceAgent.swift
//  RunAnywhere SDK
//
//  Public API for Voice Agent operations (full voice pipeline).
//  Calls C++ directly via CppBridge for all operations.
//  Events are emitted by C++ layer - no Swift event emissions needed.
//
//  Architecture:
//  - Voice agent uses SHARED handles from the individual components (STT, LLM, TTS, VAD)
//  - Models are loaded via loadSTT(), loadLLM(), loadTTS() (the individual APIs)
//  - Voice agent is purely an orchestrator for the full voice pipeline
//  - All events (including state changes) are emitted from C++
//
//  Types are defined in VoiceAgentTypes.swift
//

import CRACommons
import Foundation

// MARK: - Voice Agent Operations

public extension RunAnywhere {

    // MARK: - Component State Management

    /// Get the current state of all voice agent components (STT, LLM, TTS)
    ///
    /// Use this to check which models are loaded and ready for the voice pipeline.
    /// Models are loaded via the individual APIs (loadSTT, loadLLM, loadTTS).
    static func getVoiceAgentComponentStates() async -> VoiceAgentComponentStates {
        guard isSDKInitialized else {
            return VoiceAgentComponentStates()
        }

        let sttLoaded = await CppBridge.STT.shared.isLoaded
        let sttId = await CppBridge.STT.shared.currentModelId
        let llmLoaded = await CppBridge.LLM.shared.isLoaded
        let llmId = await CppBridge.LLM.shared.currentModelId
        let ttsLoaded = await CppBridge.TTS.shared.isLoaded
        let ttsId = await CppBridge.TTS.shared.currentVoiceId

        let sttState: ComponentLoadState
        if sttLoaded, let modelId = sttId {
            sttState = .loaded(modelId: modelId)
        } else {
            sttState = .notLoaded
        }

        let llmState: ComponentLoadState
        if llmLoaded, let modelId = llmId {
            llmState = .loaded(modelId: modelId)
        } else {
            llmState = .notLoaded
        }

        let ttsState: ComponentLoadState
        if ttsLoaded, let modelId = ttsId {
            ttsState = .loaded(modelId: modelId)
        } else {
            ttsState = .notLoaded
        }

        return VoiceAgentComponentStates(stt: sttState, llm: llmState, tts: ttsState)
    }

    /// Check if all voice agent components are loaded and ready
    static var areAllVoiceComponentsReady: Bool {
        get async {
            let states = await getVoiceAgentComponentStates()
            return states.isFullyReady
        }
    }

    // MARK: - Initialization

    /// Initialize the voice agent with configuration
    /// Events are emitted from C++ - no Swift event emissions needed
    static func initializeVoiceAgent(_ config: VoiceAgentConfiguration) async throws {
        guard isSDKInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        try await ensureServicesReady()

        let handle = try await CppBridge.VoiceAgent.shared.getHandle()

        // Build C config
        var cConfig = rac_voice_agent_config_t()

        // VAD config
        cConfig.vad_config.sample_rate = Int32(config.vadSampleRate)
        cConfig.vad_config.frame_length = config.vadFrameLength
        cConfig.vad_config.energy_threshold = config.vadEnergyThreshold

        // STT config
        if let sttModelId = config.sttModelId {
            cConfig.stt_config.model_id = (sttModelId as NSString).utf8String
        }

        // LLM config
        if let llmModelId = config.llmModelId {
            cConfig.llm_config.model_id = (llmModelId as NSString).utf8String
        }

        // TTS config
        if let ttsVoice = config.ttsVoice {
            cConfig.tts_config.voice = (ttsVoice as NSString).utf8String
        }

        let result = rac_voice_agent_initialize(handle, &cConfig)
        guard result == RAC_SUCCESS else {
            throw SDKError.voiceAgent(.initializationFailed, "Voice agent initialization failed: \(result)")
        }
    }

    /// Initialize voice agent using already-loaded models from individual APIs
    /// Events are emitted from C++ - no Swift event emissions needed
    static func initializeVoiceAgentWithLoadedModels() async throws {
        guard isSDKInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        try await ensureServicesReady()

        let handle = try await CppBridge.VoiceAgent.shared.getHandle()

        let result = rac_voice_agent_initialize_with_loaded_models(handle)
        guard result == RAC_SUCCESS else {
            throw SDKError.voiceAgent(.initializationFailed, "Failed to initialize with loaded models: \(result)")
        }
    }

    /// Check if voice agent is ready (all components initialized)
    static var isVoiceAgentReady: Bool {
        get async {
            await CppBridge.VoiceAgent.shared.isReady
        }
    }

    // MARK: - Voice Processing

    /// Process a complete voice turn: audio -> transcription -> LLM response -> synthesized speech
    static func processVoiceTurn(_ audioData: Data) async throws -> VoiceAgentResult {
        guard isSDKInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        let handle = try await CppBridge.VoiceAgent.shared.getHandle()

        var isReady: rac_bool_t = RAC_FALSE
        rac_voice_agent_is_ready(handle, &isReady)
        guard isReady == RAC_TRUE else {
            throw SDKError.voiceAgent(.notInitialized, "Voice agent not ready")
        }

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

        // C++ returns WAV format directly
        var synthesizedAudio: Data?
        if let audioPtr = cResult.synthesized_audio, cResult.synthesized_audio_size > 0 {
            synthesizedAudio = Data(bytes: audioPtr, count: cResult.synthesized_audio_size)
        }

        // Free C result
        rac_voice_agent_result_free(&cResult)

        return VoiceAgentResult(
            speechDetected: speechDetected,
            transcription: transcription,
            response: response,
            synthesizedAudio: synthesizedAudio
        )
    }

    // MARK: - Individual Operations

    /// Transcribe audio (voice agent must be initialized)
    static func voiceAgentTranscribe(_ audioData: Data) async throws -> String {
        guard isSDKInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        let handle = try await CppBridge.VoiceAgent.shared.getHandle()

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

    /// Generate LLM response (voice agent must be initialized)
    static func voiceAgentGenerateResponse(_ prompt: String) async throws -> String {
        guard isSDKInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        let handle = try await CppBridge.VoiceAgent.shared.getHandle()

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

    /// Synthesize speech (voice agent must be initialized)
    static func voiceAgentSynthesizeSpeech(_ text: String) async throws -> Data {
        guard isSDKInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        let handle = try await CppBridge.VoiceAgent.shared.getHandle()

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

    // MARK: - Cleanup

    /// Cleanup voice agent resources
    static func cleanupVoiceAgent() async {
        await CppBridge.VoiceAgent.shared.cleanup()
    }
}
