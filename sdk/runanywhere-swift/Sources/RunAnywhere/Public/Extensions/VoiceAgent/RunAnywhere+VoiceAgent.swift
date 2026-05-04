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

    /// Get the current state of all voice agent components (VAD, STT, LLM, TTS).
    ///
    /// Returns `ComponentStates` (canonical CANONICAL_API §10 name, aliased to
    /// `VoiceAgentComponentStates`). Use this to check which models are loaded
    /// and ready for the voice pipeline.
    /// Models are loaded via the individual APIs (loadSTT, loadLLM, loadTTS).
    static func getVoiceAgentComponentStates() async -> ComponentStates {
        guard isInitialized else {
            return VoiceAgentComponentStates()
        }

        if let states = try? await CppBridge.VoiceAgent.shared.componentStatesProto() {
            return states
        }

        let sttLoaded = await CppBridge.STT.shared.isLoaded
        let llmLoaded = await CppBridge.LLM.shared.isLoaded
        let ttsLoaded = await CppBridge.TTS.shared.isLoaded
        let vadLoaded = await CppBridge.VAD.shared.isModelLoaded

        return VoiceAgentComponentStates(
            stt: sttLoaded ? .loaded : .notLoaded,
            llm: llmLoaded ? .loaded : .notLoaded,
            tts: ttsLoaded ? .loaded : .notLoaded,
            vad: vadLoaded ? .loaded : .notLoaded
        )
    }

    /// Check if all voice agent components are loaded and ready
    static var areAllVoiceComponentsReady: Bool {
        get async {
            let states = await getVoiceAgentComponentStates()
            return states.isFullyReady
        }
    }

    // MARK: - Initialization

    /// Initialize the voice agent with configuration (CANONICAL_API §10).
    ///
    /// Accepts `VoiceAgentConfig` (canonical cross-SDK name, aliased to
    /// `VoiceAgentConfiguration`). Events are emitted from C++ — no Swift
    /// event emissions needed.
    static func initializeVoiceAgent(_ config: VoiceAgentConfig) async throws {
        guard isInitialized else {
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }

        try await ensureServicesReady()
        _ = try await CppBridge.VoiceAgent.shared.initialize(config)
    }

    /// Initialize voice agent using already-loaded models from individual APIs
    /// Events are emitted from C++ - no Swift event emissions needed
    static func initializeVoiceAgentWithLoadedModels() async throws {
        guard isInitialized else {
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }

        try await ensureServicesReady()

        _ = try await CppBridge.VoiceAgent.shared.initialize(RAVoiceAgentComposeConfig())
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
        guard isInitialized else {
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }

        guard await CppBridge.VoiceAgent.shared.isReady else {
            throw SDKException.voiceAgent(.notInitialized, "Voice agent not ready")
        }

        return try await CppBridge.VoiceAgent.shared.processVoiceTurnProto(audioData)
    }

    // MARK: - Individual Operations

    /// Transcribe audio (voice agent must be initialized)
    static func voiceAgentTranscribe(_ audioData: Data) async throws -> STTOutput {
        guard isInitialized else {
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }

        let handle = try await CppBridge.VoiceAgent.shared.getHandle()

        let start = Date()
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
            throw SDKException.voiceAgent(.processingFailed, "Transcription failed: \(result)")
        }

        let transcription = String(cString: ptr)
        free(ptr)

        let processingTime = Date().timeIntervalSince(start)
        let metadata = TranscriptionMetadata(
            modelId: await CppBridge.STT.shared.currentModelId ?? "voice-agent",
            processingTime: processingTime,
            audioLength: 0
        )
        return STTOutput(
            text: transcription,
            confidence: 1.0,
            wordTimestamps: nil,
            detectedLanguage: nil,
            alternatives: nil,
            metadata: metadata
        )
    }

    /// Generate LLM response (voice agent must be initialized)
    static func voiceAgentGenerateResponse(_ prompt: String) async throws -> String {
        guard isInitialized else {
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }

        let handle = try await CppBridge.VoiceAgent.shared.getHandle()

        var responsePtr: UnsafeMutablePointer<CChar>?
        let result = prompt.withCString { promptPtr in
            rac_voice_agent_generate_response(handle, promptPtr, &responsePtr)
        }

        guard result == RAC_SUCCESS, let ptr = responsePtr else {
            throw SDKException.voiceAgent(.processingFailed, "Response generation failed: \(result)")
        }

        let response = String(cString: ptr)
        free(ptr)

        return response
    }

    /// Synthesize speech (voice agent must be initialized)
    static func voiceAgentSynthesizeSpeech(_ text: String) async throws -> TTSOutput {
        guard isInitialized else {
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }

        let handle = try await CppBridge.VoiceAgent.shared.getHandle()

        let start = Date()
        var audioPtr: UnsafeMutableRawPointer?
        var audioSize: Int = 0
        let result = text.withCString { textPtr in
            rac_voice_agent_synthesize_speech(handle, textPtr, &audioPtr, &audioSize)
        }

        defer {
            if let ptr = audioPtr {
                rac_free(ptr)
            }
        }

        guard result == RAC_SUCCESS else {
            throw SDKException.voiceAgent(.processingFailed, "Speech synthesis failed: \(result)")
        }

        let audioData: Data
        if let ptr = audioPtr, audioSize > 0 {
            audioData = Data(bytes: ptr, count: audioSize)
        } else {
            audioData = Data()
        }

        let processingTime = Date().timeIntervalSince(start)
        let metadata = TTSSynthesisMetadata(
            voice: await CppBridge.TTS.shared.currentVoiceId ?? "voice-agent",
            language: "en-US",
            processingTime: processingTime,
            characterCount: text.count
        )
        return TTSOutput(
            audioData: audioData,
            format: .pcm,
            duration: 0,
            phonemeTimestamps: nil,
            metadata: metadata
        )
    }

    // MARK: - Streaming

    /// Open a stream of canonical `RAVoiceEvent` proto events for the active
    /// voice agent. Equivalent to the per-SDK `streamVoiceAgent()` entries
    /// in Kotlin, Flutter, RN, and Web (see CANONICAL_API §10).
    ///
    /// The voice agent must be initialized (e.g. via
    /// `initializeVoiceAgentWithLoadedModels()`) before calling this; the
    /// implementation will obtain the underlying handle from the SDK
    /// internals and wire a `VoiceAgentStreamAdapter` over the C ABI proto
    /// callback.
    ///
    /// Cancellation: breaking out of the consuming `for-await` loop (or
    /// cancelling the surrounding `Task`) tears down the C callback via
    /// `rac_voice_agent_set_proto_callback(handle, nullptr, nullptr)`.
    ///
    /// - Returns: `AsyncStream<RAVoiceEvent>` — yields one event per agent
    ///            state change, partial transcript, LLM token, TTS chunk,
    ///            etc. Stream finishes when the agent ends or cancellation
    ///            is observed.
    static func streamVoiceAgent() -> AsyncStream<RAVoiceEvent> {
        AsyncStream { continuation in
            // The C callback is registered on `Adapter.stream()` consumption;
            // we hop off the calling sync context to fetch the handle from
            // the actor and forward events through.
            let task = Task {
                guard isInitialized else {
                    continuation.finish()
                    return
                }

                let handle: rac_voice_agent_handle_t
                do {
                    handle = try await CppBridge.VoiceAgent.shared.getHandle()
                } catch {
                    continuation.finish()
                    return
                }

                let adapter = VoiceAgentStreamAdapter(handle: handle)
                for await event in adapter.stream() {
                    if Task.isCancelled { break }
                    continuation.yield(event)
                }
                continuation.finish()
            }

            continuation.onTermination = { @Sendable _ in
                // Cancel the consumer task; the adapter's own onTermination
                // hook deregisters `rac_voice_agent_set_proto_callback`.
                task.cancel()
            }
        }
    }

    // MARK: - Cleanup

    /// Cleanup voice agent resources
    static func cleanupVoiceAgent() async {
        await CppBridge.VoiceAgent.shared.cleanup()
    }
}

private func withOptionalCString<Result>(
    _ string: String?,
    _ body: (UnsafePointer<CChar>?) -> Result
) -> Result {
    guard let string, !string.isEmpty else {
        return body(nil)
    }
    return string.withCString { pointer in
        body(pointer)
    }
}
