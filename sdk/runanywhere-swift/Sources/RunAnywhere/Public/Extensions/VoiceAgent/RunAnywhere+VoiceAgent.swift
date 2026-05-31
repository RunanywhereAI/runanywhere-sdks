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

    /// Default Silero VAD model id seeded by every example app's catalog.
    /// Exposed so callers do not hard-code the string when invoking
    /// `ensureDefaultVAD(...)`.
    static var defaultVADModelID: String { "silero-vad" }

    /// Ensure a VAD model is loaded in the canonical lifecycle before a voice
    /// agent session starts. When no VAD model is currently registered for
    /// `.voiceActivityDetection`, attempts to load the catalogued default
    /// (`defaultVADModelID`, Silero) so the voice agent's speech-start /
    /// speech-end events fire. The energy-based fallback does not produce
    /// the lifecycle events the voice-agent orchestrator listens for, so
    /// without a VAD lifecycle load the session stays silent after init.
    ///
    /// Idempotent: returns `true` immediately when a VAD model is already
    /// loaded. Logs (but does not throw) when the optional auto-load fails;
    /// callers may inspect the return value to decide whether to surface a
    /// warning.
    ///
    /// - Parameter modelID: VAD model id to auto-load when none is current.
    ///   Defaults to `defaultVADModelID`.
    /// - Returns: `true` when a VAD model is loaded after the call;
    ///   `false` when no VAD model is loaded (auto-load failed or skipped).
    @discardableResult
    static func ensureDefaultVAD(modelID: String? = nil) async -> Bool {
        guard isInitialized else { return false }

        var currentRequest = RACurrentModelRequest()
        currentRequest.category = .voiceActivityDetection
        let snapshot = RunAnywhere.currentModel(currentRequest)
        if snapshot.found && !snapshot.modelID.isEmpty {
            return true
        }

        let targetID = modelID ?? defaultVADModelID
        guard !targetID.isEmpty else { return false }

        SDKLogger.voiceAgent.info("Auto-loading default VAD '\(targetID)' for voice-agent session")

        var loadRequest = RAModelLoadRequest()
        loadRequest.modelID = targetID
        loadRequest.category = .voiceActivityDetection
        let result = await RunAnywhere.loadModel(loadRequest)
        if !result.success {
            SDKLogger.voiceAgent.warning(
                "Default VAD '\(targetID)' auto-load failed: \(result.errorMessage) — voice agent will use energy fallback"
            )
            return false
        }
        return true
    }

    /// Initialize the voice agent from currently-loaded STT / LLM / TTS models.
    ///
    /// Composes a `RAVoiceAgentComposeConfig` from the canonical model
    /// lifecycle (`RunAnywhere.currentModel(_:)`) snapshots for
    /// `.speechRecognition`, `.language`, and `.speechSynthesis`, then
    /// forwards to `initializeVoiceAgent(_:)`. Mirrors the Kotlin / Web SDKs'
    /// `initializeVoiceAgentWithLoadedModels()` API.
    ///
    /// When `ensureVAD` is `true` (default), the SDK guarantees that a VAD
    /// model is loaded into the canonical lifecycle before initialization
    /// runs via `ensureDefaultVAD(...)`. Without this the session would
    /// silently fall back to the energy-based detector and the C++ voice
    /// agent's speech-start / speech-end lifecycle events would not fire.
    /// Set to `false` only if the caller has already loaded an explicit VAD
    /// model (or knows the energy fallback is acceptable for the deployment).
    ///
    /// - Parameter ttsVoiceID: Optional explicit voice id to pass through to
    ///   the TTS engine. For multi-voice TTS engines (e.g., Sherpa-ONNX-TTS
    ///   with Piper multi-speaker models), the voice id selects which voice
    ///   within the loaded model to use and is semantically distinct from the
    ///   TTS model id. When `nil` (the default), the engine's default voice
    ///   is used — appropriate for single-voice models. Callers using
    ///   multi-voice engines should pass the desired voice id explicitly.
    ///   Never reuse the TTS model id here — model id ≠ voice id.
    /// - Parameter ensureVAD: Whether to auto-load the catalogued default VAD
    ///   when no `.voiceActivityDetection` model is loaded. Defaults to
    ///   `true`.
    /// - Throws: `SDKException(code: .notInitialized, message: ..., category: .internal)` if the SDK has
    ///           not completed Phase 1 initialization.
    /// - Throws: `SDKException(code: .modelNotLoaded, message: ..., category: .component)` if STT, LLM,
    ///           or TTS has no model loaded.
    static func initializeVoiceAgentWithLoadedModels(
        ttsVoiceID: String? = nil,
        ensureVAD: Bool = true
    ) async throws {
        guard isInitialized else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }

        try await ensureServicesReady()

        if ensureVAD {
            _ = await ensureDefaultVAD()
        }

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
        // ttsVoiceID is the voice id *within* the loaded TTS model, NOT the
        // model id. For single-voice engines, leaving it unset lets the
        // engine pick its default voice. For multi-voice engines (Piper,
        // eSpeak-NG, Sherpa-ONNX-TTS multi-voice), the caller must supply
        // the desired voice id explicitly via the `ttsVoiceID` parameter.
        // Previous releases conflated `ttsSnap.modelID` with the voice id,
        // which produced an invalid voice selection for multi-voice models.
        if let voiceID = ttsVoiceID, !voiceID.isEmpty {
            config.ttsVoiceID = voiceID
        }

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

        try await ensureServicesReady()

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
                    try await ensureServicesReady()
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
