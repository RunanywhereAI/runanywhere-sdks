//
//  RunAnywhere+VoiceAgent.swift
//  RunAnywhere SDK
//
//  Deprecated flat voice-agent verbs. The v3 surface is
//  `RunAnywhere.voice.createSession(...)`, which owns download, load, VAD
//  residency, and pipeline wiring, and only opens the microphone on
//  `VoiceSession.start()`.
//

import CRACommons
import Foundation

public extension RunAnywhere {

    /// Initialize the voice agent with an explicit compose configuration.
    @available(*, deprecated, renamed: "voice.createSession(stt:llm:tts:vad:turnHandling:generation:downloadIfNeeded:)")
    static func initializeVoiceAgent(_ config: RAVoiceAgentComposeConfig) async throws {
        guard isReady else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        try await ensureServicesReady()
        _ = try await CppBridge.VoiceAgent.shared.getHandle()
        _ = try await CppBridge.VoiceAgent.shared.initialize(config)
    }

    /// Default Silero VAD model id declared in `idl/sdk_defaults.proto`.
    @available(*, deprecated, message: "voice.createSession ensures a VAD automatically")
    static var defaultVADModelID: String { RADefaults.VoiceAgent.defaultVadModelID }

    /// Ensure a VAD model is resident before a voice-agent session starts.
    @discardableResult
    @available(*, deprecated, message: "voice.createSession ensures a VAD automatically")
    static func ensureDefaultVAD(modelID: String? = nil) async -> Bool {
        guard isReady else { return false }

        let snapshot = loadedModelSnapshot(category: .voiceActivityDetection)
        if snapshot.found && !snapshot.modelID.isEmpty {
            return true
        }

        let targetID = modelID ?? RADefaults.VoiceAgent.defaultVadModelID
        guard !targetID.isEmpty else { return false }

        SDKLogger.voiceAgent.info("Auto-loading default VAD '\(targetID)' for voice-agent session")

        var loadRequest = RAModelLoadRequest()
        loadRequest.modelID = targetID
        loadRequest.category = .voiceActivityDetection
        let result = await performLoad(loadRequest)
        if result.hasError {
            SDKLogger.voiceAgent.warning(
                "Default VAD '\(targetID)' auto-load failed: \(result.error.message) — voice agent will use energy fallback"
            )
            return false
        }
        return true
    }

    /// Initialize the voice agent from the currently-loaded STT / LLM / TTS models.
    @available(*, deprecated, renamed: "voice.createSession(stt:llm:tts:vad:turnHandling:generation:downloadIfNeeded:)")
    static func initializeVoiceAgentWithLoadedModels(
        ttsVoiceID: String? = nil,
        ensureVAD: Bool = true
    ) async throws {
        guard isReady else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        try await ensureServicesReady()

        if ensureVAD {
            _ = await ensureDefaultVAD()
        }

        // The C++ lifecycle service is the canonical source of truth for "is
        // this modality loaded"; the per-component CppBridge actor mirrors are
        // not updated by the model-lifecycle load path.
        let sttSnap = loadedModelSnapshot(category: .speechRecognition)
        let llmSnap = loadedModelSnapshot(category: .language)
        let ttsSnap = loadedModelSnapshot(category: .speechSynthesis)

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
        // The voice id selects a voice *within* the loaded TTS model and is not
        // the model id; multi-voice engines must be given one explicitly.
        if let voiceID = ttsVoiceID, !voiceID.isEmpty {
            config.ttsVoiceID = voiceID
        }

        _ = try await CppBridge.VoiceAgent.shared.getHandle()
        _ = try await CppBridge.VoiceAgent.shared.initialize(config)
    }

    /// Per-component load status plus the aggregate `ready` flag.
    @available(*, deprecated, renamed: "componentLifecycleSnapshot(_:)")
    static func getVoiceAgentComponentStates() async throws -> RAVoiceAgentComponentStates {
        guard isReady else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        try await ensureServicesReady()
        return try await CppBridge.VoiceAgent.shared.componentStates()
    }

    /// Process a complete voice turn through the proto C++ ABI.
    @available(*, deprecated, renamed: "voice.createSession(stt:llm:tts:vad:turnHandling:generation:downloadIfNeeded:)")
    static func processVoiceTurn(_ audioData: Data) async throws -> RAVoiceAgentResult {
        guard isReady else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        try await ensureServicesReady()

        guard await CppBridge.VoiceAgent.shared.isReady else {
            throw SDKException(code: .componentNotReady, message: "Voice agent not ready", category: .component)
        }
        return try await CppBridge.VoiceAgent.shared.processVoiceTurnProto(audioData)
    }

    /// Stream voice events, capturing microphone audio while consumed.
    ///
    /// Opening the microphone as a side effect of subscribing is exactly what
    /// `VoiceSession.start()` replaces.
    @available(*, deprecated, renamed: "VoiceSession.events")
    static func streamVoiceAgent() -> AsyncStream<RAVoiceEvent> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    guard isReady else {
                        continuation.finish()
                        return
                    }

                    try await ensureServicesReady()
                    let handle = try await CppBridge.VoiceAgent.shared.getHandle()

                    let micDriver = VoiceAgentMicDriver(handle: handle)
                    let micTask = Task {
                        do {
                            try await micDriver.run()
                        } catch is CancellationError {
                            // Expected when the consumer stops the session.
                        } catch {
                            SDKLogger.voiceAgent.error("Voice-agent mic driver stopped: \(error.localizedDescription)")
                        }
                    }

                    defer { micTask.cancel() }

                    let adapter = VoiceAgentStreamAdapter(handle: handle.rawValue)
                    for await event in adapter.stream() {
                        if Task.isCancelled { break }
                        continuation.yield(event)
                    }
                } catch {
                    SDKLogger.voiceAgent.error("Voice agent stream setup failed: \(error.localizedDescription)")
                }
                continuation.finish()
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    /// Cleanup voice agent resources.
    @available(*, deprecated, renamed: "VoiceSession.close()")
    static func cleanupVoiceAgent() async {
        await CppBridge.VoiceAgent.shared.cleanup()
    }
}
