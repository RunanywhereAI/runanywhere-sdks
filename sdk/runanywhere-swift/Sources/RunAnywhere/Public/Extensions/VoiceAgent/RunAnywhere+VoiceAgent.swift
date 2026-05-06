//
//  RunAnywhere+VoiceAgent.swift
//  RunAnywhere SDK
//
//  Public API for Voice Agent operations (full voice pipeline).
//  Calls C++ directly via CppBridge for all operations.
//  Events are emitted by C++ layer - no Swift event emissions needed.
//
//  Architecture:
//  - Voice agent uses SHARED handles from individual components (STT/LLM/TTS/VAD)
//  - Models are loaded via the canonical lifecycle (`RAModelLoadRequest`)
//  - Voice agent is purely an orchestrator for the full voice pipeline
//  - All events (including state changes) are emitted from C++
//

import CRACommons
import Foundation

// MARK: - Voice Agent Operations

public extension RunAnywhere {

    /// Initialize the voice agent with configuration.
    static func initializeVoiceAgent(_ config: RAVoiceAgentComposeConfig) async throws {
        guard isInitialized else {
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }

        try await ensureServicesReady()
        _ = try await CppBridge.VoiceAgent.shared.initialize(config)
    }

    /// Initialize the voice agent from currently-loaded STT / LLM / TTS models.
    ///
    /// Reads the model IDs from the per-component bridge actors
    /// (`CppBridge.STT.shared`, `.LLM.shared`, `.TTS.shared`, `.VAD.shared`),
    /// builds a `RAVoiceAgentComposeConfig` from them, and forwards to
    /// `initializeVoiceAgent(_:)`. Mirrors the Kotlin / Web SDKs'
    /// `initializeVoiceAgentWithLoadedModels()` API.
    ///
    /// - Throws: `SDKException.general(.notInitialized, ...)` if the SDK has
    ///           not completed Phase 1 initialization.
    /// - Throws: `SDKException.voiceAgent(.modelNotLoaded, ...)` if STT, LLM,
    ///           or TTS has no model loaded.
    static func initializeVoiceAgentWithLoadedModels() async throws {
        guard isInitialized else {
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }

        try await ensureServicesReady()

        let sttModelId = await CppBridge.STT.shared.currentModelId
        let llmModelId = await CppBridge.LLM.shared.currentModelId
        let ttsVoiceId = await CppBridge.TTS.shared.currentVoiceId

        var missing: [String] = []
        if sttModelId?.isEmpty ?? true { missing.append("STT") }
        if llmModelId?.isEmpty ?? true { missing.append("LLM") }
        if ttsVoiceId?.isEmpty ?? true { missing.append("TTS") }
        guard missing.isEmpty else {
            throw SDKException.voiceAgent(
                .modelNotLoaded,
                "Cannot initialize voice agent: Models not loaded: \(missing.joined(separator: ", "))"
            )
        }

        var config = RAVoiceAgentComposeConfig()
        if let id = sttModelId { config.sttModelID = id }
        if let id = llmModelId { config.llmModelID = id }
        if let id = ttsVoiceId { config.ttsVoiceID = id }

        _ = try await CppBridge.VoiceAgent.shared.initialize(config)
    }

    /// Get the current voice-agent component states (per-component load status
    /// and the aggregate `ready` flag).
    ///
    /// Mirrors the Kotlin / Web SDKs' `getVoiceAgentComponentStates()` API.
    /// Thin forwarder over `CppBridge.VoiceAgent.shared.componentStatesProto()`.
    ///
    /// - Returns: Proto `RAVoiceAgentComponentStates` with per-component
    ///            `ComponentLifecycleState` and a computed `ready` flag.
    /// - Throws: `SDKException.general(.notInitialized, ...)` if the SDK has
    ///           not completed Phase 1 initialization.
    static func getVoiceAgentComponentStates() async throws -> RAVoiceAgentComponentStates {
        guard isInitialized else {
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }

        try await ensureServicesReady()
        return try await CppBridge.VoiceAgent.shared.componentStatesProto()
    }

    /// Process a complete voice turn through the proto C++ ABI.
    static func processVoiceTurn(_ audioData: Data) async throws -> RAVoiceAgentResult {
        guard isInitialized else {
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }

        guard await CppBridge.VoiceAgent.shared.isReady else {
            throw SDKException.voiceAgent(.notInitialized, "Voice agent not ready")
        }

        return try await CppBridge.VoiceAgent.shared.processVoiceTurnProto(audioData)
    }

    /// Open a stream of canonical `RAVoiceEvent` proto events for the active
    /// voice agent.
    ///
    /// Cancellation: breaking out of the consuming `for-await` loop (or
    /// cancelling the surrounding `Task`) tears down the C callback via
    /// `rac_voice_agent_set_proto_callback(handle, nullptr, nullptr)`.
    static func streamVoiceAgent() -> AsyncStream<RAVoiceEvent> {
        AsyncStream { continuation in
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
                task.cancel()
            }
        }
    }

    /// Cleanup voice agent resources.
    static func cleanupVoiceAgent() async {
        await CppBridge.VoiceAgent.shared.cleanup()
    }
}
