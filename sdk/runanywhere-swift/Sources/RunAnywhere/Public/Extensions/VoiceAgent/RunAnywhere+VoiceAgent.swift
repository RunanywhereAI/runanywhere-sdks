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
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }

        try await ensureServicesReady()
        let handle = try await CppBridge.VoiceAgent.shared.getHandle()
        _ = try await CppBridge.VoiceAgent.shared.initialize(handle: handle, config)
    }

    /// Initialize the voice agent from currently-loaded STT / LLM / TTS models.
    ///
    /// Composes a `RAVoiceAgentComposeConfig` from the canonical model
    /// lifecycle (`RunAnywhere.currentModel(_:)`) snapshots for
    /// `.speechRecognition`, `.language`, and `.speechSynthesis`, then
    /// forwards to `initializeVoiceAgent(_:)`. Mirrors the Kotlin / Web SDKs'
    /// `initializeVoiceAgentWithLoadedModels()` API.
    ///
    /// - Throws: `SDKException(code: .notInitialized, message: ..., category: .internal)` if the SDK has
    ///           not completed Phase 1 initialization.
    /// - Throws: `SDKException(code: .modelNotLoaded, message: ..., category: .component)` if STT, LLM,
    ///           or TTS has no model loaded.
    static func initializeVoiceAgentWithLoadedModels() async throws {
        guard isInitialized else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }

        try await ensureServicesReady()

        // The C++ lifecycle service is the canonical source of truth for
        // "is this modality loaded"; the per-component CppBridge actor
        // mirrors are not updated by RunAnywhere.loadModel(_:). Query the
        // lifecycle directly, matching the iOS example app and the rest of
        // the public Swift surface (STT/TTS/VLM readiness checks).
        var sttRequest = RACurrentModelRequest()
        sttRequest.category = .speechRecognition
        let sttSnap = RunAnywhere.currentModel(sttRequest)

        var llmRequest = RACurrentModelRequest()
        llmRequest.category = .language
        let llmSnap = RunAnywhere.currentModel(llmRequest)

        var ttsRequest = RACurrentModelRequest()
        ttsRequest.category = .speechSynthesis
        let ttsSnap = RunAnywhere.currentModel(ttsRequest)

        var missing: [String] = []
        if !sttSnap.found || sttSnap.modelID.isEmpty { missing.append("STT") }
        if !llmSnap.found || llmSnap.modelID.isEmpty { missing.append("LLM") }
        if !ttsSnap.found || ttsSnap.modelID.isEmpty { missing.append("TTS") }
        guard missing.isEmpty else {
            throw SDKException(
                code: .modelNotLoaded,
                message: "Cannot initialize voice agent: Models not loaded: \(missing.joined(separator: ", "))",
                category: .component
            )
        }

        var config = RAVoiceAgentComposeConfig()
        config.sttModelID = sttSnap.modelID
        config.llmModelID = llmSnap.modelID
        config.ttsVoiceID = ttsSnap.modelID

        let handle = try await CppBridge.VoiceAgent.shared.getHandle()
        _ = try await CppBridge.VoiceAgent.shared.initialize(handle: handle, config)
    }

    /// Get the current voice-agent component states (per-component load status
    /// and the aggregate `ready` flag).
    ///
    /// Mirrors the Kotlin / Web SDKs' `getVoiceAgentComponentStates()` API.
    /// Thin forwarder over `CppBridge.VoiceAgent.shared.componentStatesProto()`.
    ///
    /// - Returns: Proto `RAVoiceAgentComponentStates` with per-component
    ///            `ComponentLifecycleState` and a computed `ready` flag.
    /// - Throws: `SDKException(code: .notInitialized, message: ..., category: .internal)` if the SDK has
    ///           not completed Phase 1 initialization.
    static func getVoiceAgentComponentStates() async throws -> RAVoiceAgentComponentStates {
        guard isInitialized else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }

        try await ensureServicesReady()
        let handle = try await CppBridge.VoiceAgent.shared.requireExistingHandle()
        return try await CppBridge.VoiceAgent.shared.componentStatesProto(handle: handle)
    }

    /// Process a complete voice turn through the proto C++ ABI.
    static func processVoiceTurn(_ audioData: Data) async throws -> RAVoiceAgentResult {
        guard isInitialized else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }

        guard await CppBridge.VoiceAgent.shared.isReady else {
            throw SDKException(code: .notInitialized, message: "Voice agent not ready", category: .component)
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
