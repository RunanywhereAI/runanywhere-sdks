//
//  HandleManager.swift
//  RunAnywhere SDK
//
//  Internal actor for managing all C++ component handles.
//  Replaces individual Capability actors with a centralized, thread-safe manager.
//
//  This is the single point of contact between Swift and C++ components.
//  All handle lifecycle management happens here.
//

import CRACommons
import Foundation

/// Internal actor that manages all C++ component handles.
/// Provides thread-safe access to LLM, STT, TTS, and VAD components.
internal actor HandleManager {
    static let shared = HandleManager()

    // MARK: - Handles

    private var llmHandle: rac_handle_t?
    private var sttHandle: rac_handle_t?
    private var ttsHandle: rac_handle_t?
    private var vadHandle: rac_handle_t?

    // MARK: - Model State

    private var llmModelId: String?
    private var sttModelId: String?
    private var ttsVoiceId: String?

    // MARK: - Logger

    private let logger = SDKLogger(category: "HandleManager")

    // MARK: - LLM

    /// Get or create LLM handle
    func getLLMHandle() throws -> rac_handle_t {
        if let handle = llmHandle {
            return handle
        }
        var newHandle: rac_handle_t?
        let result = rac_llm_component_create(&newHandle)
        guard result == RAC_SUCCESS, let handle = newHandle else {
            throw SDKError.llm(.notInitialized, "Failed to create LLM component: \(result)")
        }
        llmHandle = handle
        return handle
    }

    /// Check if LLM model is loaded
    var isLLMLoaded: Bool {
        guard let handle = llmHandle else { return false }
        return rac_llm_component_is_loaded(handle) == RAC_TRUE
    }

    /// Get current LLM model ID
    var currentLLMModelId: String? { llmModelId }

    /// Load LLM model
    func loadLLMModel(_ modelPath: String, modelId: String) throws {
        let handle = try getLLMHandle()
        let result = modelPath.withCString { pathPtr in
            rac_llm_component_load_model(handle, pathPtr)
        }
        guard result == RAC_SUCCESS else {
            throw SDKError.llm(.modelLoadFailed, "Failed to load model: \(result)")
        }
        llmModelId = modelId
        logger.info("LLM model loaded: \(modelId)")
    }

    /// Unload LLM model
    func unloadLLM() {
        guard let handle = llmHandle else { return }
        rac_llm_component_cleanup(handle)
        llmModelId = nil
        logger.info("LLM model unloaded")
    }

    /// Cancel LLM generation
    func cancelLLM() {
        guard let handle = llmHandle else { return }
        rac_llm_component_cancel(handle)
    }

    // MARK: - STT

    /// Get or create STT handle
    func getSTTHandle() throws -> rac_handle_t {
        if let handle = sttHandle {
            return handle
        }
        var newHandle: rac_handle_t?
        let result = rac_stt_component_create(&newHandle)
        guard result == RAC_SUCCESS, let handle = newHandle else {
            throw SDKError.stt(.notInitialized, "Failed to create STT component: \(result)")
        }
        sttHandle = handle
        return handle
    }

    /// Check if STT model is loaded
    var isSTTLoaded: Bool {
        guard let handle = sttHandle else { return false }
        return rac_stt_component_is_loaded(handle) == RAC_TRUE
    }

    /// Get current STT model ID
    var currentSTTModelId: String? { sttModelId }

    /// Load STT model
    func loadSTTModel(_ modelPath: String, modelId: String) throws {
        let handle = try getSTTHandle()
        let result = modelPath.withCString { pathPtr in
            rac_stt_component_load_model(handle, pathPtr)
        }
        guard result == RAC_SUCCESS else {
            throw SDKError.stt(.modelLoadFailed, "Failed to load model: \(result)")
        }
        sttModelId = modelId
        logger.info("STT model loaded: \(modelId)")
    }

    /// Unload STT model
    func unloadSTT() {
        guard let handle = sttHandle else { return }
        rac_stt_component_cleanup(handle)
        sttModelId = nil
        logger.info("STT model unloaded")
    }

    /// Check if STT supports streaming
    var sttSupportsStreaming: Bool {
        guard let handle = sttHandle else { return false }
        return rac_stt_component_supports_streaming(handle) == RAC_TRUE
    }

    // MARK: - TTS

    /// Get or create TTS handle
    func getTTSHandle() throws -> rac_handle_t {
        if let handle = ttsHandle {
            return handle
        }
        var newHandle: rac_handle_t?
        let result = rac_tts_component_create(&newHandle)
        guard result == RAC_SUCCESS, let handle = newHandle else {
            throw SDKError.tts(.notInitialized, "Failed to create TTS component: \(result)")
        }
        ttsHandle = handle
        return handle
    }

    /// Check if TTS voice is loaded
    var isTTSLoaded: Bool {
        guard let handle = ttsHandle else { return false }
        return rac_tts_component_is_loaded(handle) == RAC_TRUE
    }

    /// Get current TTS voice ID
    var currentTTSVoiceId: String? { ttsVoiceId }

    /// Load TTS voice
    func loadTTSVoice(_ voicePath: String, voiceId: String) throws {
        let handle = try getTTSHandle()
        let result = voicePath.withCString { pathPtr in
            rac_tts_component_load_voice(handle, pathPtr)
        }
        guard result == RAC_SUCCESS else {
            throw SDKError.tts(.modelLoadFailed, "Failed to load voice: \(result)")
        }
        ttsVoiceId = voiceId
        logger.info("TTS voice loaded: \(voiceId)")
    }

    /// Unload TTS voice
    func unloadTTS() {
        guard let handle = ttsHandle else { return }
        rac_tts_component_cleanup(handle)
        ttsVoiceId = nil
        logger.info("TTS voice unloaded")
    }

    // MARK: - VAD

    /// Get or create VAD handle
    func getVADHandle() throws -> rac_handle_t {
        if let handle = vadHandle {
            return handle
        }
        var newHandle: rac_handle_t?
        let result = rac_vad_component_create(&newHandle)
        guard result == RAC_SUCCESS, let handle = newHandle else {
            throw SDKError.vad(.notInitialized, "Failed to create VAD component: \(result)")
        }
        vadHandle = handle
        return handle
    }

    /// Check if VAD is initialized
    var isVADInitialized: Bool {
        guard let handle = vadHandle else { return false }
        return rac_vad_component_is_initialized(handle) == RAC_TRUE
    }

    /// Initialize VAD with configuration
    func initializeVAD(sampleRate: Int32, channels: Int32) throws {
        let handle = try getVADHandle()
        let result = rac_vad_component_initialize(handle)
        guard result == RAC_SUCCESS else {
            throw SDKError.vad(.initializationFailed, "Failed to initialize VAD: \(result)")
        }
        logger.info("VAD initialized")
    }

    /// Cleanup VAD
    func cleanupVAD() {
        guard let handle = vadHandle else { return }
        rac_vad_component_cleanup(handle)
        logger.info("VAD cleaned up")
    }

    // MARK: - Voice Agent

    private var voiceAgentHandle: rac_voice_agent_handle_t?

    /// Create voice agent with shared handles from individual components
    func createVoiceAgent() throws -> rac_voice_agent_handle_t {
        if let handle = voiceAgentHandle {
            return handle
        }

        // Get handles from all components
        let llm = try getLLMHandle()
        let stt = try getSTTHandle()
        let tts = try getTTSHandle()
        let vad = try getVADHandle()

        var newHandle: rac_voice_agent_handle_t?
        let result = rac_voice_agent_create(llm, stt, tts, vad, &newHandle)

        guard result == RAC_SUCCESS, let handle = newHandle else {
            throw SDKError.voiceAgent(.initializationFailed, "Failed to create voice agent: \(result)")
        }

        voiceAgentHandle = handle
        logger.info("Voice agent created with shared handles")
        return handle
    }

    /// Get voice agent handle (creates if needed)
    func getVoiceAgentHandle() throws -> rac_voice_agent_handle_t {
        try createVoiceAgent()
    }

    /// Check if voice agent is ready
    var isVoiceAgentReady: Bool {
        guard let handle = voiceAgentHandle else { return false }
        var ready: rac_bool_t = RAC_FALSE
        let result = rac_voice_agent_is_ready(handle, &ready)
        return result == RAC_SUCCESS && ready == RAC_TRUE
    }

    /// Cleanup voice agent
    func cleanupVoiceAgent() {
        guard let handle = voiceAgentHandle else { return }
        rac_voice_agent_cleanup(handle)
        rac_voice_agent_destroy(handle)
        voiceAgentHandle = nil
        logger.info("Voice agent cleaned up")
    }

    // MARK: - Cleanup

    /// Destroy all handles (called on SDK shutdown)
    func destroyAll() {
        // Destroy voice agent first (it uses other handles)
        if let handle = voiceAgentHandle {
            rac_voice_agent_destroy(handle)
            voiceAgentHandle = nil
        }
        if let handle = llmHandle {
            rac_llm_component_destroy(handle)
            llmHandle = nil
            llmModelId = nil
        }
        if let handle = sttHandle {
            rac_stt_component_destroy(handle)
            sttHandle = nil
            sttModelId = nil
        }
        if let handle = ttsHandle {
            rac_tts_component_destroy(handle)
            ttsHandle = nil
            ttsVoiceId = nil
        }
        if let handle = vadHandle {
            rac_vad_component_destroy(handle)
            vadHandle = nil
        }
        logger.info("All handles destroyed")
    }

    /// Reset for testing
    func reset() {
        destroyAll()
    }
}
